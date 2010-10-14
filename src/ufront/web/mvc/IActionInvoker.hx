package ufront.web.mvc;

/**
 * ...
 * @author Andreas Soderlund
 */
interface IActionInvoker 
{
	function invokeAction(controllerContext : ControllerContext, actionName : String) : Bool;
}