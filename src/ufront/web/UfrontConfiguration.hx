package ufront.web;

import ufront.web.Controller;
import ufront.api.*;
import ufront.web.session.*;
import ufront.auth.*;
import haxe.web.Dispatch.DispatchConfig;
import ufront.web.context.*;
import ufront.module.*;
import ufront.app.UFMiddleware;
import ufront.app.UFErrorHandler;
import ufront.handler.ErrorPageHandler;
import ufront.web.session.InlineSessionMiddleware;

/**
	Small configuration options that affect a ufront application.

	Used in `ufront.web.UfrontApplication`
**/
typedef UfrontConfiguration = {
	/** 
		Is mod_rewrite or similar being used?  
		If not, query strings will be filtered out of the URLs.
		Default = true;
	**/
	?urlRewrite:Bool,
	
	/** 
		A base path for this app relative to the root of the server.  
		If supplied, this will be filtered from URLs.
		Default = "/" (app is at root of webserver)
	**/
	?basePath:String,

	/**
		The directory 
		
		This should be specified relative to the script directory (fetched using `HttpRequest.scriptDirectory`).  You can either have it as a subdirectory, (eg "uf-content") or in a parent directory (eg "../uf-content")

		There should not be a leading slash, and a trailing slash is optional.

		Default = "uf-content"
	**/
	?contentDirectory:String,
	
	/**
		If specified, then traces are logged to the file specified by this path.

		This should be set relative to `contentDirectory`. 

		Default = null; (don't log)
	**/
	?logFile:Null<String>,
	
	/**
		Disable traces going to the browser console?
		Could be useful if you have sensitive information in your traces.
		Default = false;
	**/
	?disableBrowserTrace:Bool,

	/**
		The request middleware to use with this application

		Default is `[ new InlineSessionMiddleware() ]`
	**/
	?requestMiddleware:Array<UFRequestMiddleware>,
	
	/**
		The response middleware to use with this application

		Default is `[ new InlineSessionMiddleware() ]`
	**/
	?responseMiddleware:Array<UFResponseMiddleware>,
	
	/**
		The error handlers to use with this application
	**/
	?errorHandlers:Array<UFErrorHandler>,

	/**
		Controllers to add to the Dependency Injector.

		These classes will be added to the `DispatchHandler`'s injector.

		Default is a list of all `ufront.web.Controller` classes, fetched using `CompileTime.getAllClasses()`
	**/
	?controllers:Null<Iterable<Class<Controller>>>,
	
	/**
		APIs to add to the Dependency Injector.

		These classes will be added to the `DispatchHandler`'s injector and the `RemotingHandler`'s injector.

		Default is a list of all `ufront.api.UFApi` classes, fetched using `CompileTime.getAllClasses()`
	**/
	?apis:Null<Iterable<Class<UFApi>>>,

	/**
		A method which can be used to generate a session for the current request, as required.

		By default, this is `FileSession.create.bind(_, "sessions", null, 0)`

		This means using `ufront.web.session.FileSession`, saving to the "sessions" folder, with a default session variable name, and an expiry of 0 (when window closed)
	**/
	?sessionFactory:UFSessionFactory,

	/**
		A method which can be used to generate an AuthHandler for the current request, as required.

		By default, this is `EasyAuth.create.bind(_,null)`

		This means it will create an `ufront.auth.EasyAuth` handler using the current session, and the default variable name to store the ID in the session.
	**/
	?authFactory:UFAuthFactory
}

class DefaultUfrontConfiguration {

	/**
		Fetch a default `UfrontConfiguration`.

		The values here are as explained in the documentation for each field of `UfrontConfiguration`.

		If you do not supply a UfrontConfiguration object to your `UfrontApplication`, or if your object does not specify all the required values, it will use these values as a fallback.

		Defaults for each value are described in the documentation for each field in `UfrontConfiguration`
	**/
	public static function get():UfrontConfiguration {
		var inlineSession = new InlineSessionMiddleware();
		return {
			urlRewrite:true,
			basePath:'/',
			contentDirectory:'uf-content',
			logFile:null,
			disableBrowserTrace: false,
			controllers: cast CompileTime.getAllClasses( Controller ),
			apis: cast CompileTime.getAllClasses( UFApi ),
			sessionFactory: FileSession.getFactory("sessions", null, 0),
			requestMiddleware: [inlineSession],
			responseMiddleware: [inlineSession],
			errorHandlers: [ new ErrorPageHandler() ],
			authFactory: 
				#if ufront_easyauth 
					EasyAuth.getFactory()
				#else 
					YesBoss.getFactory() 
				#end
		}
	}
}