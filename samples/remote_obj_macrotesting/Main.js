// Generated by Haxe 3.4.6
(function () { "use strict";
var HxOverrides = function() { };
HxOverrides.iter = function(a) {
	return { cur : 0, arr : a, hasNext : function() {
		return this.cur < this.arr.length;
	}, next : function() {
		return this.arr[this.cur++];
	}};
};
var Main = function() { };
Main.main = function() {
	var a = new A(1);
	a.x = 5;
	console.log(a.update("world"));
};
var A = function(x) {
	this.x = x;
};
A.prototype = {
	update: function(a) {
		var out = "";
		out += a;
		return out;
	}
};
Main.main();
})();