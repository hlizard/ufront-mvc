package ufront.web.session;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import ufront.web.context.HttpContext;
import ufront.web.HttpCookie;
import ufront.web.session.UFHttpSessionState;
import thx.error.NotImplemented;
import haxe.ds.StringMap;
import haxe.Serializer;
import haxe.Unserializer;
import thx.error.NullArgument;
import tink.CoreApi;
using StringTools;

/**
	A session implementation using flat files.

	Files are saved to the folder `savePath`, with one file per session.  The folder must be writeable by the web server.

	Each session has a unique ID, which is randomly generated and used as the file.

	The contents of the file are a serialized StringMap representing the current session.  The serialization is done using `haxe.Serializer` and `haxe.Unserializer`.

	The session ID is sent to the client as a Cookie.  When reading the SessionID, Cookies are checked first, followed by GET/POST parameters.

	When searching the parameters or cookies for the Session ID, the name to search for is defined by the `sessionName` property.
**/
class FileSession implements UFHttpSessionState
{
	// Statics

	/**
		Get a factory for FileSessions so one can be created for each context.
	
		@param savePath - relative path to directory where sessions will be saved.
		@param sessionName - the name of the variable to store the sessionID in.
		@param expire - the number of seconds the session should last.  Default is 0.  If the value is 0 the session does not have an expiry time.
	**/
	public static function getFactory( ?savePath:String, ?sessionName:String, ?expire:Int=0 ) {
		if ( _factory==null || _factory.savePath!=savePath || _factory.sessionName!=sessionName || _factory.expire!=expire ) 
			_factory = new FileSessionFactory( savePath, sessionName, expire );
		
		return _factory;
	}
	static var _factory:FileSessionFactory;

	/**
		The default session name to use if none is provided.

		The default value is "UfrontSessionID".  You can change this static value to set a new default.
	**/
	public static var defaultSessionName:String = "UfrontSessionID";

	/**
		The default savePath.

		The default value is "sessions/".  You can change this static value to set a new default.
	**/
	public static var defaultSavePath:String = "sessions/";

	/**
		The default expiry value.

		By default this is 0.  You can change this static value to set a new default.
	**/
	public static var defaultExpiry:Int = 0;

	// Private variables 

	var context:HttpContext;
	var started:Bool;
	var commitFlag:Bool;
	var closeFlag:Bool;
	var regenerateFlag:Bool;
	var expiryFlag:Bool;
	var sessionID:String;
	var oldSessionID:Null<String>;
	var sessionData:StringMap<Dynamic>;

	// Public members

	/**
		Construct a new session object.

		This does not create the session file or commit any data, rather, it sets up the object so that read or writes can then happen.

		Data is read during `init` and written during `commit`.

		A new session object should be created for each request, and it will then associate itself with the correct session file for the given user.
	**/
	public function new( context:HttpContext, ?savePath:String, ?sessionName:String, ?expire:Null<Int> ) {
		NullArgument.throwIfNull( context );
		this.context = context;
		this.sessionName = (sessionName!=null) ? sessionName : defaultSessionName;
		this.expiry = (expiry!=null && expiry>0) ? expiry : defaultExpiry;
		
		// sanitise and set the savePath
		if (savePath==null) savePath = defaultSavePath;
		savePath = Path.addTrailingSlash( savePath );
		if (!savePath.startsWith("/")) savePath = context.contentDirectory + savePath;
		this.savePath = savePath;

		started = false;
		commitFlag = false;
		closeFlag = false;
		regenerateFlag = false;
		expiryFlag = false;
		sessionData = null;
		sessionID = null;
		oldSessionID = null;
	}

	/**
		The variable name to reference the session ID.

		This will be the name set in the Cookie sent to the client, or the name to search for in the parameters or cookies.

		This can only be set in the constructor.
	**/
	public var sessionName(default,null):String;

	/**
		The lifetime/expiry of the cookie, in seconds.  A value of 0 represents expiry when the browser window is closed.

		This can only be set in the constructor.
	**/
	public var expiry(default,null):Int;

	/**
		The save path for the session files.

		This should be absolute, or relative to the `HttpContext.contentDirectory`

		Relative paths should not have a leading slash.
		If a trailing slash is not included, it will be added.
	**/
	public var savePath(default,null):String;

	/**
		Set the number of seconds the session should last

		Note in this implementation only the cookie expiry is affected - the user could manually override this or send the session variable in the request parameters, and the session would still work.
	**/
	public function setExpiry( e:Int ) {
		expiry = e;
	}

	/**
		Initiate the session.

		This will check for an existing session ID.  If one exists, it will read and unserialize the session data from that session's file.

		If a session does not exist, one will be created.

		This is called before any other operations which require access to the current session.
	**/
	public function init():Surprise<Noise,String> {
		var t = Future.trigger();
		
		if ( !started ) {
			if( FileSystem.exists(savePath.substr(0, -1)) ) {
				var id = getID();

				var file : String;
				var fileData : String;

				// Try to restore an existing session
				if ( id!=null ) {
					testValidId( id );
					file = getSessionFilePath( id );
					if ( !FileSystem.exists(file) ) {
						id = null;
					}
					else {
						fileData = try File.getContent( file ) catch ( e:Dynamic ) null;
						if ( fileData!=null ) {
							try 
								sessionData = cast( Unserializer.run(fileData), StringMap<Dynamic> )
							catch ( e:Dynamic ) 
								fileData = null; // invalid data
						}
						if ( fileData==null ) {
							// delete file and start new session
							id = null;
							try FileSystem.deleteFile( file ) catch( e:Dynamic ) {}; 
						}
					}
				}

				// No session existed, or it was invalid - start a new one
				if( id==null ) {
					sessionData = new StringMap<Dynamic>();
					started = true;

					do {
						id = generateSessionID();
						file = savePath + id + ".sess";
					} while( FileSystem.exists(file) );
					
					// Create the file so no one else takes it
					File.saveContent( file, "" );

					var expire = ( expiry==0 ) ? null : DateTools.delta( Date.now(), 1000.0*expiry );
					var path = '/'; // TODO: Set cookie path to application path, right now it's global.
					var domain = null; 
					var secure = false;

					var sessionCookie = new HttpCookie( sessionName, id, expire, domain, path, secure );
					context.response.setCookie( sessionCookie );

					commit();
				}

				sessionID = id;
				started = true;
				t.trigger( Success(Noise) );
			}
			else t.trigger( Failure('Neko session savepath not found: ' + savePath.substr(0, -1)) );
		}
		else t.trigger( Success(Noise) );

		return t.asFuture();
	}

	/**
		Commit if required.

		Throws a String if the commit failed (usually because of no permission to write to disk)
	**/
	public function commit():Surprise<Noise,String> {
		var t = Future.trigger();
		var handled = false;

		if ( commitFlag && sessionData!=null ) {
			handled = true;
			try {
				var filePath = getSessionFilePath(sessionID);
				var content = Serializer.run(sessionData);
				File.saveContent(filePath, content);
				t.trigger( Success(Noise) );
			}
			catch( e:Dynamic ) {
				t.trigger( Failure('Unable to save session: $e') );
			}
		}
		if ( closeFlag ) {
			handled = true;
			t.trigger( Failure("NotImplemented: close the session, delete the file, expire the cookie") );
		}
		if ( regenerateFlag ) {
			handled = true;
			t.trigger( Failure("NotImplemented: use regenerated ID to rename file and update cookie") );
		}
		if ( expiryFlag ) {
			handled = true;
			t.trigger( Failure("NotImplemented: change expiry on cookie") );
		}

		if ( !handled ) t.trigger( Success(Noise) );

		return t.asFuture();
	}

	/**
		Retrieve an item from the session data
	**/
	public inline function get( name:String ):Dynamic {
		checkStarted();
		return sessionData.get( name );
	}

	/**
		Set an item in the session data.

		Note this will not commit the value to a file until dispose() is called (generally at the end of a request)
	**/
	public inline function set( name:String, value:Dynamic ):Void {
		init();
		sessionData.set( name, value );
		commitFlag = true;
	}

	/**
		Check if a session has the specified item.
	**/
	public inline function exists( name:String ):Bool {
		if ( !isActive() ) return false;
		checkStarted();
		return sessionData.exists( name );
	}

	/**
		Remove an item from the session
	**/
	public inline function remove( name:String ):Void {
		checkStarted();
		sessionData.remove(name);
		commitFlag = true;
	}

	/**
		Empty all items from the current session data without closing the session
	**/
	public inline function clear():Void {
		if ( sessionData!=null && isActive() ) {
			sessionData = new StringMap<Dynamic>();
			commitFlag = true;
		}
	}

	/**
		Regenerate the ID for this session, renaming the file on the server and sending a new session to the 
	**/
	public function regenerateID():Surprise<String,String> {
		var t = Future.trigger();
		oldSessionID = sessionID;
		sessionID = generateSessionID();
		regenerateFlag = true;
		t.trigger( Success(sessionID) );
		return t.asFuture();
	}
	
	/**
		Whether or not the current session is active.

		This is determined by if a sessionID exists, which will happen if init() has been called or if a SessionID was provided in the request context (via Cookie or GET/POST parameter etc)
	**/
	public inline function isActive():Bool {
		return getID()!=null;
	}
	
	/**
		Return the current ID
	**/
	public inline function getID():String {
		if ( sessionID==null ) sessionID = context.request.cookies[sessionName];
		if ( sessionID==null ) sessionID = context.request.params[sessionName];
		return sessionID;
	}

	/**
		Close the session.

		The sessionData and sessionID will be set to null, and the session will be flagged for deletion (when `commit` is called)
	**/
	public function close():Void {
		init();
		sessionData = null;
		sessionID = null;
		closeFlag = true;
		commitFlag = true;
	}

	// Private methods 
	
	inline function getSessionFilePath( id:String ) {
		return '$savePath$id.sess';
	}
	
	inline function generateSessionID() {
		return Random.string(40);
	}

	inline function checkStarted() {
		if ( !started ) 
			throw "Trying to access session data before calling init()";
	}

	static var validID = ~/^[a-zA-Z0-9]+$/;
	static inline function testValidId( id:String ):Void {
		if( id!=null )
			if(!validID.match(id)) 
				throw "Invalid session ID.";
	}
}

class FileSessionFactory implements UFSessionFactory {
	
	public var savePath(default,null):Null<String>;
	public var sessionName(default,null):Null<String>;
	public var expire(default,null):Int;

	public function new( ?savePath:String, ?sessionName:String, ?expire:Int=0 ) {
		this.savePath = savePath;
		this.sessionName = sessionName;
		this.expire = expire;
	}

	public function create( context:HttpContext ) {
		return new FileSession( context, savePath, sessionName, expire );
	}

}