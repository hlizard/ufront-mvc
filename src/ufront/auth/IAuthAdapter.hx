package ufront.auth;

import tink.CoreApi;

interface IAuthAdapter<T>
{
	public function authenticate():Surprise<T,PermissionError>;
}