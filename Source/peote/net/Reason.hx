package peote.net;

@:enum abstract Reason(Int) from Int to Int 
{
	public static inline var DISCONNECT :Int = 0; // disconnected from peote-server (joint-owner/user)
	public static inline var CLOSE      :Int = 1; // owner closed joint or user leaves
	public static inline var KICK       :Int = 2; // user was kicked by joint-owner
	                                    
	public static inline var ID         :Int = 10; // can't enter/open joint with this id (another or none exists)
	public static inline var FULL       :Int = 11; // malicious input
	public static inline var MAX        :Int = 12; // malicious input
                                        
	public static inline var MALICIOUS  :Int = 20; // malicious input
}