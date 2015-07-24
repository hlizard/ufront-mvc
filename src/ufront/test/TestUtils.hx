package ufront.test;

#if !macro
import ufront.web.context.*;
import ufront.web.HttpError;
import ufront.web.session.UFHttpSession;
import ufront.auth.*;
import haxe.PosInfos;
import ufront.web.Controller;
import ufront.log.OriginalTraceLogger;
import ufront.app.UfrontApplication;
import ufront.app.UfrontConfiguration;
import ufront.web.result.ActionResult;
import ufront.core.MultiValueMap;
import minject.Injector;
#if utest import utest.Assert; #end
#if mockatoo using mockatoo.Mockatoo; #end
using tink.CoreApi;
using ufront.core.InjectionTools;
#end

/**
A set of functions to make it easier to mock and test various ufront classes and interfaces.

These helpers have been designed for use with static extension: `using ufront.test.TestUtils`.
When you use static extension in this way, `NaturalLanguageTests` and `Mockatoo` are also included for static extension.

The methods in `NaturalLanguageTests` are shortcuts to these methods, but named in a way to make your automated tests very readable when using static extension.

Every `mock` function uses `Mockatoo` for mocking, see the [Github Readme](https://github.com/misprintt/mockatoo/) and [Developer Guide](https://github.com/misprintt/mockatoo/wiki/Developer-Guide) for more information.

Please note both `utest` and `mockatoo` libraries must be included for these methods to be available.
**/
class TestUtils {
	#if (utest && mockatoo && !macro)
		/**
		Mock a HttpContext.

		Usage:

		```
		TestUtils.mockHttpContext( '/home' );
		'/home'.mockHttpContext();
		TestUtils.mockHttpContext( '/home', request, response, session, auth );
		'/home'.mockHttpContext( request, response, session, auth );
		```

		Details:

		- The URI provided is the raw `REQUEST_URI` and so can include a query string etc.
		- The uri is used for `request.uri` if the request is being mocked.
		  (If the request object is given, not mocked, the supplied Uri is ignored.)
		- `getRequestUri` calls the real method, so will process filters on `request.uri`
		- The request, response, session and auth return either the supplied value, or are mocked.
		- Session uses `VoidSession` as a default mock object, auth uses `YesBossAuthHandler` by default.
		- `setUrlFilters` and `generateUri` call the real methods.

		@param uri The URI to use for the mock request. eg `/blog/first-post.html?source=social`. This is ignored if `request` is provided.
		@param method (optional) The HTTP method to use. eg `POST` or `GET`. This is ignored if `request` is provided. Default is `"GET"`.
		@param params (optional) Any HTTP parameters to use. eg `[ name=>"Jason", gender=>"Male" ]`. This is ignored if `request` is provided.
		@param injector (optional) A custom `Injector` to use in the HTTP Context.
		@param request (optional) A custom `HttpRequest` to use. If supplied, this will be used instead of `uri`, `method` and `params`.
		@param response (optional) A custom `HttpResponse` to use.
		@param session (optional) A custom `UFHttpSession` to use. Default is `VoidSession`.
		@param auth (optional) A custom `UFAuthHandler` to use. Default is `YesBossAuthHandler`.
		@return A mock `HttpContext`, using the requested values.
		**/
		public static function mockHttpContext( uri:String, ?method:String, ?params:MultiValueMap<String>, ?injector:Injector, ?request:HttpRequest, ?response:HttpResponse, ?session:UFHttpSession, ?auth:UFAuthHandler ):HttpContext {
			HttpError.throwIfNull( uri, "uri" );
			if ( injector==null ) {
				injector = new Injector();
			}
			if ( request==null ) {
				request = HttpRequest.mock();
				@:privateAccess request.uri.returns( uri );
				@:privateAccess request.scriptDirectory.returns( "./" );
				@:privateAccess request.params.returns( (params!=null) ? params : new MultiValueMap() );
				@:privateAccess request.httpMethod.returns( (method!=null) ? method.toUpperCase() : "GET" );
				@:privateAccess request.clientHeaders.returns( new MultiValueMap() );
			}
			if ( response==null ) {
				response = HttpResponse.spy();
				response.flush().stub();
			}
			if ( session==null && injector.hasMapping(UFHttpSession)==false ) {
				session = new ufront.web.session.VoidSession();
			}
			if ( auth==null && injector.hasMapping(UFAuthHandler)==false ) {
				auth = new ufront.auth.YesBossAuthHandler();
			}

			return new HttpContext( request, response, injector, session, auth, [] );
		}

		/**
		Test a route on a `UfrontApplication` or a `Controller` by executing the request.

		If the app is supplied, the request will be executed with the given context.
		If only the controller is supplied, a simple UfrontApplication will be instantiated.
		It is recommended that your app have `disableBrowserTrace: true` and `errorHandlers: []` in it's configuration, to make debugging your unit test simpler.

		If the route is executed successfully, the `RouteTestResult` (an object holding the `UfrontApplication` and `HttpContext`) is returned so that you can analyze it further.
		See `TestUtils.assertSuccess()`, `TestUtils.assertFailure`, `TestUtils.responseShouldBe` and `TestUtils.checkResult` for methods that can run further tests on a `RouteTestResult`.

		If an error is encountered, the `HttpError` is returned as a `Failure`.

		**Asynchronous Test**

		Because a `UfrontApplication` is designed to execute asynchronously, during `testRoute` we call `Assert.createAsync` to let our testing framework know it must wait for completion.
		Because of this, every time you call `testRoute()` you must be careful to call `TestUtils.finishAsyncTest()` after you have run your tests.

		**Example:**

		```
		"/blog/"
		  .mockHttpContext()
		  .assertSuccess()
		  .finishAsyncTest();
		```

		@param context The mocked `HttpContext` to use for executing a test request.
		@param app (optional) The `UfrontApplication` to execute for the test request.
		@param controller (optional) The index controller to start routing from. Must be supplied if `app` is not supplied.
		@return A `RequestTestContext` containing the context of the request as well as the end result.
		**/
		public static function testRoute( context:HttpContext, ?app:UfrontApplication, ?controller:Class<Controller>, ?p:PosInfos ):RequestTestContext {
			if ( app==null && controller==null )
				throw new Error('Either app or controller must be supplied to testRoute', p);
			if ( app==null ) {
				var ufrontConf:UfrontConfiguration = {
					indexController: controller,
					disableBrowserTrace: true,
					disableServerTrace: true,
					errorHandlers: [],
				}
				app = new UfrontApplication( ufrontConf );
				app.addLogHandler( new OriginalTraceLogger() );
			}
			@:privateAccess context.injector.parent = app.injector;
			var resultSurprise = app.execute( context );
			// Make sure our test suite waits for the test to complete.
			resultSurprise.handle( Assert.createAsync() );
			return {
				result: resultSurprise,
				app: app,
				context: context
			};
		}

		/**
		Check that the result of the `testRoute()` call was a success, and that the parameters supplied matched.

		If the result was not a success, this will fail.
		If the result was a success, but the dispatch didn't match the given controller, action or args, it will fail.
		If a failure occurs, `Assert.fail` will be called, giving an error message at the location this method was called from.

		For matching, the following rules apply:

		- Controllers are matched using their name (`Type.getClassName()`).
		- Action is matched using string equality, for the same method name on the controller.
		- Args are checked for the same length first.
		- If they have the same length, the arguments are checked using exact equality.
		- If `controller`, `action` or `args` are not supplied, then they are not checked.

		This can be chained together with other methods as so:

		```
		var app = "/home/".mockHttpContext().testRoute(IndexController).assertSuccess(HomeController, "doDefault", []);
		```

		@param testContext The outcome from a call to `this.testRoute()`.
		@param controller (optional) The controller or sub-controller that was expected to handle the request. Usually a `Controller` class.
		@param action (optional) The name of the action/method that was expected to be executed on the controller.
		@param args (optional) The collection of arguments that were expected to be passed to the controller action.
		@return The same `testContext` that was passed in.
		**/
		public static function assertSuccess( testContext:RequestTestContext, ?controller:Class<Dynamic>, ?action:String, ?args:Array<Dynamic>, ?p:PosInfos ):RequestTestContext {
			var doneCallback = Assert.createAsync();
			testContext.result.handle(function (outcome) switch outcome {
				case Success( _ ):
					var ctx = testContext.context.actionContext;
					Assert.notNull( ctx );

					// If a controller type was specified, check it matches.
					if ( controller!=null ) {
						if ( !Std.is(ctx.controller, controller) ) {
							var expectedName = Type.getClassName(controller);
							var actualName = Type.getClassName( Type.getClass(ctx.controller) );
							if ( expectedName!=actualName ) {
								Assert.fail( '[$actualName] was not equal to expected controller type [$expectedName] after dispatching', p );
							}
						}
					}

					// If an action was specified, check it matches.
					if ( action!=null )
						if ( action!=ctx.action )
							Assert.fail( '[${ctx.action}] was not equal to expected action [$action] after dispatching', p );

					// If an args array was specified, check length and args match.
					if ( args!=null ) {
						Assert.equals( args.length, ctx.args.length, 'Expected ${args.length} arguments for MVC action, but had ${ctx.args.length}', p );
						for ( i in 0...args.length ) {
							var expected = args[i];
							var actual = ctx.args[i];
							var recursive = true;
							Assert.same( expected, actual, recursive, 'Expected argument ${i+1} for MVC action `$action()` to be `$expected`, but was `$actual`', p );
						}
					}
					doneCallback();
				case Failure( f ):
					var exceptionStack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
					Assert.fail( 'Expected routing to succeed, but it did not (failed with error $f, ${f.data} ${exceptionStack})', p );
					doneCallback();
			});
			return testContext;
		}

		/**
		Check that the result of the `testRoute()` call was a failure, and that the parameters supplied matched.

		If the result was not a failure, this will call `Assert.fail()`, giving an error at the position this method was called from.
		If the result was indeed a failure, then we also check if the `code`, `message` and `innerData` parameters of the given error match those supplied in this function call (if any).

		This can be chained together with other methods as so:

		```
		var error = "/home/".mockHttpContext().testRoute(IndexController).assertFailure(404);
		```

		@param testContext The outcome from a call to `this.testRoute()`.
		@param code (optional) Assert that the error code from the request matches this value.
		@param message (optional) Assert that the error message from the request matches this value.
		@param innerData (optional) Assert that the inner data of the request's error matches this inner data, using `Assert.same()`.
		@return The same `testContext` that was passed in.
		**/
		public static function assertFailure( testContext:RequestTestContext, ?code:Null<Int>, ?message:Null<String>, ?innerData:Null<Dynamic>, ?p:PosInfos ):RequestTestContext {
			var doneCallback = Assert.createAsync();
			testContext.result.handle(function processOutcome(outcome) {
				switch outcome {
					case Success( _ ):
						Assert.fail( 'Expected routing to fail, but it was a success', p );
						doneCallback();
					case Failure( failure ):
						if ( code!=null )
							if ( code!=failure.code )
								Assert.fail( 'Failure code [${failure.code}] was not equal to expected failure code [$code]', p );
						if ( message!=null )
							if ( message!=failure.message )
								Assert.fail( 'Failure message [${failure.message}] was not equal to expected failure message [$message]', p );
						if ( innerData!=null )
							Assert.same( innerData, failure.data, true, 'Failure data [${failure.data}] was not equal to expected failure data [$innerData]', p );
						Assert.isTrue(true);
						doneCallback();
				}
			});
			return testContext;
		}

		/**
		Assert that the HTTP Response to be sent to the client matches this expected response.

		Please note, this uses exact string equality, so will only be useful for very simple tests.
		You can use `TestUtils.checkResult()` for a more intricate test.

		@param testContext The outcome from a call to `this.testRoute()`.
		@param expectedResponse The expected content of the `HttpResponse`.
		@return The same `testContext` that was passed in.
		**/
		public static function responseShouldBe( testContext:RequestTestContext, expectedResponse:String, ?p:PosInfos ):RequestTestContext {
			var doneCallback = Assert.createAsync();
			testContext.result.handle( function(outcome) {
				Assert.equals( expectedResponse, testContext.context.response.getBuffer(), p );
				doneCallback();
			});
			return testContext;
		}

		/**
		Test that the `ActionResult` from the request is as we expect it.

		You can specify the `expectedResultType` to check that the `ActionResult` returned by your controller actions is what you expect.

		Optionally, you can also provide a `check` function, which has additional checks in it.
		This function will only be executed if the result was the expected type.

		__Example:__

		```
		"/tags/list.json"
		  .mockHttpContext()
		  .testRoute(AppRoutes)
		  .assertSuccess(TagController,"listTagsJson",[])
		  .checkResult(JsonResult);
		"/tags/list.html"
		  .mockHttpContext()
		  .testRoute(AppRoutes)
		  .assertSuccess(TagController,"listTags",[])
		  .checkResult(ViewResult, function() {
		    Assert.equals("List all Tags",viewResult.data["title"]);
		    Assert.same(FromEngine("/tag/listTags.html"),viewResult.templateSource);
		    Assert.same(FromEngine("/listTags.html"),viewResult.layoutSource);
		  });
		```

		@param testContext The outcome from a call to `this.testRoute()`.
		@param expectedResultType The class you are expecting your result to be. For example, a `JsonResult`.
		@param check (optional) A function to execute with additional tests, so you can analyze the result in more detail.
		@return The same `testContext` that was passed in.
		**/
		public static function checkResult<T:ActionResult>( testContext:RequestTestContext, expectedResultType:Class<T>, ?check:T->Void, ?p:PosInfos ):RequestTestContext {
			var doneCallback = Assert.createAsync();
			testContext.result.handle( function(outcome) switch outcome {
				case Success(_):
					var res = testContext.context.actionContext.actionResult;
					Assert.is( res, expectedResultType, 'Expected result to be ${Type.getClassName(expectedResultType)}, but it was ${Type.getClassName(Type.getClass(res))}', p );
					if ( check!=null && Std.is(res,expectedResultType) ) {
						check( cast res );
					}
					doneCallback();
				case Failure(_):
					// We do not assert a failure here, as `TestUtils.assertSuccess()` will already check that case, without blocking this test.
					doneCallback();
			});
			return testContext;
		}

		/**
		Run a function to perform further tests, passing the `testContext` to the given function.

		@param testContext The outcome from a call to `this.testRoute()`.
		@param check A function to execute with additional tests, so you can analyze the response in more detail.
		@return The same `testContext` that was passed in.
		**/
		public static function check( testContext:RequestTestContext, check:Callback<RequestTestContext> ):RequestTestContext {
			var doneCallback = Assert.createAsync();
			testContext.result.handle(function(_) {
				check.invoke( testContext );
				doneCallback();
			});
			return testContext;
		}

		/**
		Call a callback function after the test request has finished executing.

		This can be useful to either:

		- Run more tests and checks against the current request.
		- Call a `done()` method or similar to allow your test environment to know this test has finished.

		@param testContext The outcome from a call to `this.testRoute()`.
		@param callback A callback function to execute. The function should be `Void->Void` or `?Dynamic->Void`.
		@return The same `testContext` that was passed in.
		**/
		public static function onComplete( testContext:RequestTestContext, callback:Callback<Dynamic> ):RequestTestContext {
			var doneCallback = Assert.createAsync();
			testContext.result.handle(function(_) {
				callback.invoke( null );
				doneCallback();
			});
			return testContext;
		}

		/**
		Dispose of the app once the request has completed.
		This is useful in that it disposes of any modules that require it, and restores the original trace function.
		You should always call this after you have finished running your current set of tests.
		**/
		public static function disposeApp( testContext:RequestTestContext ):RequestTestContext {
			var doneCallback = Assert.createAsync();
			testContext.app.dispose().handle(function(_) {
				doneCallback();
			});
			return testContext;
		}
	#end
}

/**
`NaturalLanguageTests` is a collection of aliases for the methods in `TestUtils`.

It is designed to let you write powerful tests in language that is easy to read, so your tests have a more obvious purpose.
Let's you write powerful tests in a fairly natural language.

It is located in the same module as `TestUtils`, and so is included in static extension.
It also helps to do an import wildcard on the statics:

```haxe
import ufront.test.TestUtils.NaturalLanguageTests.*;
using ufront.test.TestUtils;
```

**Examples:**

```haxe
// A simple example:
whenIVisit("/home")
.onTheController( HomeController )
.itShouldLoad( HomeController, "homepage" )
.itShouldReturn( ViewResult );

// Or a bit more complex:
whenIVisit("/blog/2015-03-02/23-pictures-of-my-cat")
.onTheController( Routes )
.itShouldLoad( BlogController, "showPost", ["2015-03-02","23-pictures-of-my-cat"] )
.itShouldReturn( ViewResult, function(viewResult) {
  Assert.equals( "23 Pictures of my cat", viewResult.data["title"] );
  Assert.same( FromEngine("/blog/showPost.html"), viewResult.templateSource );
  // Or using `Buddy` style tests:
  viewResult.data["date"].should.be( "2nd April 2015" );
  viewResult.layoutSource.should.be( FromEngine("/layout.html")  );
});

// Test submitting a form (POST request):
var testMailer = new TestMailer();
whenISubmit([ "name"=>"Jason", "message"=>"Do you have more cat pictures?" ])
.to("/contact/")
.andInjectAValue( UFMailer, testMailer )
.onTheApp( myUfrontWebsite )
.itShouldLoad( HomeController, "sendContactEmail" )
.theResponseShouldBe( ViewResult, function(vr) {
  viewResult.templateSource.should.be(FromEngine("/home/sendContactEmail.html"));
  viewResult.data["name"].should.be("Jason");
})
.andAlsoCheck(function() {
  testMailer.messagesSent.length.should.be(2);
  testMailer.messagesSent[0].subject.should.be("New Website Contact from Jason");
  testMailer.messagesSent[1].subject.should.be("Thanks for getting in touch - we'll get back to you soon");
})
.pleaseWork();

// Kitchen sink example 1:
whenIVisit("/search")
.withTheParameters([ "q"=>"Ufront" ])
.withTheSessionHandler( new VoidSession() )
.withTheAuthHandler( new NobodyAuthHandler() )
.andInjectAValue( String, "uf-content", "contentDirectory" )
.onTheController( SearchController )
.itShouldLoad( SearchController, "searchFor", [{q:"Ufront"}] )
.itShouldReturn( ViewResult, function(vr) {
  vr.templateSource.should.be( FromEngine("search/searchFor.html") );
});

// Kitchen sink example 2:
whenISubmit([ "username"=>"admin", "password"=>"wrongpassword" ])
.to("/login")
.andInjectAClass( UFMailer, TestMailer )
.onTheApp( myUfrontApp )
.itShouldFail()
.itShouldFailWith( 403, "Bad Password" )
.theResponseShouldBe( "<html><body>Bad password</body></html>" );
.andAlsoCheck(function(testContext) {
  testContext.app.messages.length.should.be(0);
});
```
**/
class NaturalLanguageTests {


	/** Inject a value into the `HttpContext.injector`. This is an alias for `InjectionTools.injectValue()`. **/
	public static macro function andInjectAValue<T>( context:haxe.macro.Expr.ExprOf<HttpContext>, cl, val, ?named ):haxe.macro.Expr.ExprOf<HttpContext> {
		var injectorExpr = macro $context.injector;
		var injectExpr = ufront.core.InjectionTools.injectValue( injectorExpr, cl, val, named );
		return macro {
			$injectExpr;
			$context;
		};
	}

	/** Inject a class into the `HttpContext.injector`. This is an alias for `InjectionTools.injectClass()`. **/
	public static macro function andInjectAClass<T>( context:haxe.macro.Expr.ExprOf<HttpContext>, cl, ?cl2, ?singleton, ?named ):haxe.macro.Expr.ExprOf<HttpContext> {
		var injectorExpr = macro $context.injector;
		var injectExpr = ufront.core.InjectionTools.injectClass( injectorExpr, cl, cl2, singleton, named );
		return macro {
			$injectExpr;
			$context;
		};
	}

	#if (utest && mockatoo && !macro)

		/**
		Begin a test sentance for a page visit:

		```
		whenIVisit("/blog").onTheApp(ufApp).itShouldLoad(BlogController,"postList",[]);
		```

		This is an alias for `TestUtils.mockHttpContext`.
		**/
		public static inline function whenIVisit( uri:String, ?method:String, ?params:MultiValueMap<String>, ?injector:Injector, ?request:HttpRequest, ?response:HttpResponse, ?session:UFHttpSession, ?auth:UFAuthHandler ):HttpContext
			return TestUtils.mockHttpContext( uri, method, params, injector, request, response, session, auth );


		/**
		A helper to add parameters to your mock request.

		```
		whenIVist("/search").withTheParams([ "q"=>"search query"])
		```
		**/
		public static function withTheParams( context:HttpContext, params:MultiValueMap<String> ):HttpContext {
			for ( key in params.keys() ) {
				for ( val in params.getAll(key) )
					context.request.params.add( key, val );
			}
			return context;
		}

		/**
		Begin a test sentance for a form submission:

		```
		whenISubmit([ "name"=>"Jason" ]).to("/contact/").onTheController(HomeController).itShouldLoad(HomeController,"contact",["Jason"])
		```

		This should be followed by the `NaturalLanguageTests.to()` function.

		This function is a no-op, returning the parameters it starts with - it exists merely to make your tests more readable as an English sentance.
		**/
		public static inline function whenISubmit( params:MultiValueMap<String> ):MultiValueMap<String>
			return params;

		/**
		Continue a test sentance for a form submission:

		```
		whenISubmit([ "name"=>"Jason" ]).to("/contact/").onTheController(HomeController).itShouldLoad(HomeController,"contact",["Jason"])
		```

		This should follow a sentance started with `NaturalLanguageTests.whenISubmit()`.

		It will turn a MultiValueMap into a POST request using `TestUtils.mockHttpContext`.
		**/
		public static inline function to( params:MultiValueMap<String>, postAddress:String ):HttpContext
			return whenIVisit( postAddress, "POST", params );

		/** Use this `UFHttpSession` for this `HttpContext.session`. **/
		public static inline function withTheSessionHandler( context:HttpContext, session:UFHttpSession ):HttpContext {
			@:privateAccess context.session = session;
			return context;
		}

		/** Use this `UFAuthHandler` for this `HttpContext.auth`. **/
		public static inline function withTheAuthHandler( context:HttpContext, auth:UFAuthHandler ):HttpContext {
			@:privateAccess context.auth = auth;
			return context;
		}

		/** Test the given `HttpContext` on a given app. This is an alias for `TestUtils.testRoute` **/
		public static inline function onTheApp( context:HttpContext, app:UfrontApplication, ?p:PosInfos ):RequestTestContext
			return TestUtils.testRoute( context, app, p );

		/** Test the given `HttpContext` on a given controller. This is an alias for `TestUtils.testRoute` **/
		public static inline function onTheController( context:HttpContext, controller:Class<Controller>, ?p:PosInfos ):RequestTestContext
			return TestUtils.testRoute( context, controller, p );

		/** Check that a test request loaded as expected. This is an alias for `TestUtils.assertSuccess` **/
		public static inline function itShouldLoad( testContext:RequestTestContext, ?controller:Class<Dynamic>, ?action:String, ?args:Array<Dynamic>, ?p:PosInfos ):RequestTestContext
			return TestUtils.assertSuccess( testContext, controller, action, args, p );

		/** Check that a test request failed. This is an alias for `TestUtils.assertFailure` **/
		public static inline function itShouldFail( testContext:RequestTestContext, ?p:PosInfos ):RequestTestContext
			return TestUtils.assertFailure( testContext, p );

		/** Check that a test request failed in the expected way. This is an alias for `TestUtils.assertFailure` **/
		public static inline function itShouldFailWith( testContext:RequestTestContext, ?code:Int, ?msg:String, ?data:Dynamic, ?p:PosInfos ):RequestTestContext
			return TestUtils.assertFailure( testContext, code, msg, data, p );

		/** Check the return type (`ActionResult`) of the request, and optionally perform additional checks on the `ActionResult`. This is an alias for `TestUtils.checkResult` **/
		public static inline function itShouldReturn<T:ActionResult>( testContext:RequestTestContext, expectedResultType:Class<T>, ?check:T->Void, ?p:PosInfos ):RequestTestContext
			return TestUtils.checkResult( testContext, expectedResultType, check, p );

		/** Check that the `HttpResponse` content to be sent to the client is as expected. This is an alias for `TestUtils.responseShouldBe` **/
		public static inline function theResponseShouldBe( testContext:RequestTestContext, expectedResponse:String, ?p:PosInfos ):RequestTestContext
			return TestUtils.responseShouldBe( testContext, expectedResponse, p );

		/** Perform some more arbitrary checks once the request has completed. This is an alias for `TestUtils.check` **/
		public static inline function andThenCheck( testContext:RequestTestContext, check:Callback<RequestTestContext>, ?p:PosInfos ):RequestTestContext
			return TestUtils.check( testContext, check );

		/** Alert our async test runner that the testing is complete. This is an alias for `TestUtils.onComplete` **/
		public static inline function andFinishWith( testContext:RequestTestContext, ?callback:Callback<Dynamic> ):RequestTestContext
			return TestUtils.onComplete( testContext, callback );

		/** Dispose the current application when you're done running tests with it. This is an alias for `TestUtils.disposeApp` **/
		public static inline function finishTest( testContext:RequestTestContext ):RequestTestContext
			return TestUtils.disposeApp( testContext );
	#end
}

#if !macro
	#if mockatoo
	/**
	A shortcut to `Mockatoo` so that `using ufront.test.TestUtils;` implies `using mockatoo.Mockatoo` as well.
	**/
	typedef TMockatoo = mockatoo.Mockatoo;
	#end

	/**
	A collection of objects which describes the context for the current test, and is passed through each of the functions in `TestUtils`.
	**/
	typedef RequestTestContext = {
		/** The asynchronous result of the `app.execute()` call. Wait for this to complete before testing the results. **/
		public var result:Surprise<Noise,Error>;
		/** The `UfrontApplication` that the test was executed on. **/
		public var app:UfrontApplication;
		/** The `HttpContext` of the current test request. **/
		public var context:HttpContext;
	}
#end
