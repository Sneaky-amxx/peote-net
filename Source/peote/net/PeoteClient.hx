package peote.net;

import haxe.io.Bytes;
import haxe.Timer;
import peote.io.PeoteBytesOutput;

/**
 * by Sylvio Sell - rostock 2015
 */

class PeoteClient
{
	public var events:PeoteClientEvents;
	
	public var jointNr(default, null):Int;
	public var jointId(default, null):String;
	public var server(default, null):String = "";
	public var port(default, null):Int;

	public var localPeoteServer:PeoteServer = null;
	public var localUserNr:Int;
	
	var peoteJointSocket:PeoteJointSocket;
	
	var input:Bytes;
	var input_pos:Int = 0;
	var input_end:Int = 0;
	var chunk_size:Int = 0;
	
	public function new(events:PeoteClientEvents) 
	{
		this.events = events;
		if (events.onDataChunk != null) input = Bytes.alloc((65536+2)*2); // TODO
	}

	// -----------------------------------------------------------------------------------
	// ENTER JOINT -----------------------------------------------------------------------
	
	public function enter(server:String, port:Int, jointId:String):Void 
	{
		if (this.server == "")
		{
			this.server = server;
			this.port = port;
			this.jointId = jointId;
			PeoteNet.enterJoint(this, server, port, jointId);
		}
		else
		{
			throw("Error: PeoteClient already connected");
			events.onError(this, 255); // TODO
		}
	}

	// -----------------------------------------------------------------------------------
	// LEAVE JOINT -----------------------------------------------------------------------
	
	public function leave():Void 
	{
		PeoteNet.leaveJoint(this, this.server, this.port, this.jointNr);
		this.server = "";
	}

	// -----------------------------------------------------------------------------------
	// SEND DATA -------------------------------------------------------------------------
	public var last_delay:Int = 0;
	public var last_time:Float = 0;
	public function send(bytes:Bytes):Void
	{	
		if (localPeoteServer == null) this.peoteJointSocket.sendDataToJointIn(this.jointNr, bytes );
		else {
			var delay = Std.int(Math.max(0, last_delay - (Timer.stamp() - last_time) * 1000))
			          + Std.int(localPeoteServer.netLag + 1000 * bytes.length / localPeoteServer.netSpeed);
			last_delay = delay; // TODO: for local testing put a LIMIT here for OVERFLOW!!!!!
			last_time = Timer.stamp();
			Timer.delay(function() {
				localPeoteServer._onData(localPeoteServer.jointNr, localUserNr , bytes);
			}, delay);
		}
	}

	public function sendChunk(bytes:Bytes):Void
	{
		if (bytes.length <= 0) throw("Error(sendChunk): can't send zero length chunk");
		else if (bytes.length > 65536)  throw("Error(sendChunk): max chunksize is 65536 Bytes");
		else {
			var chunksize:Bytes = Bytes.alloc(2);
			chunksize.setUInt16(0, bytes.length-1);
			send( chunksize );
			send( bytes );			
		}
	}
	
	// -----------------------------------------------------------------------------------
	// CALLBACKS -------------------------------------------------------------------------
	
	public function _onEnterJoint(peoteJointSocket:PeoteJointSocket, jointNr:Int):Void
	{
		this.peoteJointSocket = peoteJointSocket;
		this.jointNr = jointNr;
		events.onEnter(this);
 	}
	
	public function _onEnterJointError(errorNr:Int):Void // bei FEHLER
	{
		this.server = "";
		events.onError(this, errorNr );
 	}
	
	public function _onDisconnect(jointNr:Int, reason:Int):Void 
	{
		events.onDisconnect(this, reason);	
 	}
	
	
	public function _onData(jointNr:Int, bytes:Bytes):Void
	{
		//trace("onData: " + bytes.length);
		if (events.onDataChunk != null) {
		
			if (input_pos == input_end) { input_pos = input_end = 0; }
			
			//var debugOut = "";for (i in 0...bytes.length) debugOut += bytes.get(i) + " ";trace("data:" + debugOut);
			if (input_end + bytes.length > input.length) trace("ERROR Client: out of BOUNDS");
			input.blit(input_end, bytes, 0, bytes.length );
			
			input_end += bytes.length;
			
			if (chunk_size == 0 && input_end-input_pos >=2 ) {
				chunk_size = input.getUInt16(input_pos) + 1; // read chunk size
				//trace("chunksize readed:" + chunk_size, input.get(input_pos),input.get(input_pos+1));
				input_pos += 2;
			}
			
			if ( chunk_size != 0 && input_end-input_pos >= chunk_size )
			{
				var b:Bytes = Bytes.alloc(chunk_size);
				//trace(" ---> onDataChunk: " + b.length + "Bytes ( start:"+input_pos+" end:"+input_end+ ")",b.get(0), b.get(1), b.get(2));
				b.blit(0, input, input_pos, chunk_size);
				input_pos += chunk_size;
				chunk_size = 0;
				events.onDataChunk(this, b );
			}
		}
		else events.onData(this, bytes);
	
	}
	
	// -----------------------------------------------------------------------------------
	// RPC -------------------------------------------------------------------------

	public function getRemoteFunctions(f:Dynamic):Dynamic {
		
		// TODO: return a NEW object that has only the following functiona:
		
		f.message = function (p1:String, p2:Int):Void {
			var output = new PeoteBytesOutput();
			output.writeByte(0);//trace("send procedureNr:"+0);
			output.writeString(p1);
			output.writeInt32(p2);
			sendChunk(output.getBytes()); // TODO: faster without chunks
		}
		f.test = function (p1:Int):Void {
			var output = new PeoteBytesOutput();
			output.writeByte(1);//trace("send procedureNr:"+1);
			output.writeInt32(p1);
			sendChunk(output.getBytes());
		}
		return f;
	}
	


}