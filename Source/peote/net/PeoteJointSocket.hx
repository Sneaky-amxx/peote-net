package peote.net;

import haxe.io.Bytes;

/**
 * ...
 * @author Sylvio Sell
 */

import peote.socket.PeoteSocket;

class PeoteJointSocket
{

	var peoteSocket:PeoteSocket;
	
	var connected:Bool = false;
	
	var onConnectCallback:Bool -> String -> Void;
	var onCloseCallback:String -> Void;
	var onErrorCallback:String -> Void;
	
	
	var ownJointDataCallback:Map<Int,Int -> Int -> Bytes -> Void>;
	var inJointDataCallback :Map<Int,Int -> Bytes -> Void> ;
	
	var ownUserConnectCallback   :Map<Int,Bytes -> Void> ;
	var ownUserDisconnectCallback:Map<Int,Bytes -> Void> ;
	var inDisconnectCallback     :Map<Int,Bytes -> Void>;
	
	var waitingCommandCallbacks:Map<Int,Bytes -> Void> ;
	
	var input:Bytes;
	var input_pos:Int = 0;
	var input_end:Int = 0;
	
	var bytes_left:Int = 0;
	var command_mode:Bool = false;
	var joint_nr:Int = -1;
	var user_nr:Int = -1;
	
	
	public function new(server:String, port: Int,
						onConnectCallback:Bool -> String -> Void = null,
						onCloseCallback:String -> Void = null,
						onErrorCallback:String -> Void = null
						) 
	{
		this.onConnectCallback = onConnectCallback;
		this.onCloseCallback = onCloseCallback;
		this.onErrorCallback = onErrorCallback;
		
		input = Bytes.alloc(32767*2+4);
		
		ownJointDataCallback = new Map<Int,Int -> Int -> Bytes -> Void>();
		inJointDataCallback  = new Map<Int,Int -> Bytes -> Void>();
		
		ownUserConnectCallback    = new Map<Int,Bytes -> Void>() ;
		ownUserDisconnectCallback = new Map<Int,Bytes -> Void>() ;
		inDisconnectCallback      = new Map<Int,Bytes -> Void>() ;
		
		waitingCommandCallbacks = new Map<Int,Bytes -> Void>();
		
		peoteSocket = new PeoteSocket( { 
				onConnect: this.onConnect,
				onClose: this.onClose,
				onError: this.onError,
				onData: this.onData
		});
	}
	
	public function connect(server:String, port:Int):Void
	{
		if ( connected )
		{	trace("PeoteNet Error: socket is already connected and has to close before new connect()");
		}
		else
		{
			connected = true;
			peoteSocket.connect(server, port);	
		}
	}
	public function close():Void 
	{
		if ( !connected )
		{	trace("PeoteNet Error: socket is not connected and nothing to close()");
		}
		else
		{
			peoteSocket.close();
		}
	}
	private function onConnect(isConnected:Bool, msg:String):Void
	{	//trace("onConnect");
		if (!isConnected)
		{	//cant connect
			connected = false;
			if (onConnectCallback != null) onConnectCallback(isConnected, msg);
		}
		else
		{	// is connected
			if (onConnectCallback != null) onConnectCallback(isConnected, msg);
		}
	}
	private function onClose(msg:String):Void
	{	//trace("onClose");
		connected = false;
		if (onCloseCallback != null) onCloseCallback(msg);
	}
	private function onError(msg:String):Void
	{	//trace("onError");
		connected = false;
		if (onErrorCallback != null) onErrorCallback(msg);
	}
	private function addCommandCallback(max:Int, commandCallback:Bytes -> Void):Int
	{
		var nr:Int = 1; // nr. 0 ist KEINE Antwort sondern command vom server
		while (waitingCommandCallbacks.exists(nr) && nr <= max)  // TODO: achtung, wenn viele schnell hintereinander dan: RACE CONDITION
		{
			nr++;
		}
		if (nr > max)
		{
			nr = -1; // ERROR
		}
		else
		{    // TODO: achtung, wenn viele schnell hintereinander dan: RACE CONDITION
			if (!waitingCommandCallbacks.exists(nr)) waitingCommandCallbacks.set(nr, commandCallback);
			else nr = -1; // ERROR
		}
		return(nr);
	}

	public function createOwnJoint(joint_id:String, commandCallback:Int -> Void,
												dataCallback:Int -> Int -> Bytes -> Void,
												userConnectCallback:Int -> Int-> Void,
												userDisconnectCallback:Int -> Int -> Int -> Void,
												errorCallback:Int -> Void = null):Void 
	{
		var bytes:Bytes = Bytes.ofString(joint_id);
		if (bytes.length <= 255)
		{		
			var nr:Int = addCommandCallback(255, function(command_chunk:Bytes):Void 
							{ onCreateOwnJoint(command_chunk, commandCallback, dataCallback,
															userConnectCallback, userDisconnectCallback,
															errorCallback);
							}
							);
			
			if (nr != -1)
			{
				peoteSocket.writeByte(0); // 0 leitet command ein (das waere sonst die chunk-size, die kann aber niemals 1 sein)
				
				peoteSocket.writeByte(0); // create command
				peoteSocket.writeByte(nr); // command nummer fuer die spaetere antwort
				
				// ab hier aber alles fuer die ID in einen kleinen-CHUNK pressen
				peoteSocket.writeByte(bytes.length);
				peoteSocket.writeBytes(bytes);
				
				peoteSocket.flush();
			} // TODO: else error for commandCallback overflow
		}
		else
		{
			if (errorCallback != null) errorCallback(-3); // joint_id to long
		}		
	}
	
	private function onCreateOwnJoint(command_chunk:Bytes, commandCallback:Int -> Void,
															dataCallback:Int -> Int -> Bytes -> Void,
															userConnectCallback:Int -> Int-> Void,
															userDisconnectCallback:Int -> Int -> Int -> Void,
															errorCallback:Int -> Void = null):Void 
	{
		//trace("onCreateOwnJoint: ANTWORT ...");
		// chunk auswerten:
		if (command_chunk.get(0) == 0) // -> OK 
		{	
			var joint_nr = command_chunk.get(1); // -> joint_nr lesen
			ownJointDataCallback.set(joint_nr, dataCallback);
			ownUserConnectCallback.set(joint_nr, function(command_chunk:Bytes)
												{ onUserConnect(userConnectCallback, joint_nr, command_chunk); }
										);
			ownUserDisconnectCallback.set(joint_nr, function(command_chunk:Bytes)
												{ onUserDisconnect(userDisconnectCallback, joint_nr, command_chunk); }
										);
			
			commandCallback(joint_nr);
		}
		else
		{	// Fehler
			if (errorCallback != null) errorCallback(command_chunk.get(1));
		}
	}
	
	private function onUserConnect(userConnectCallback:Int -> Int -> Void, joint_nr:Int, command_chunk:Bytes):Void
	{
		userConnectCallback(joint_nr, command_chunk.get(0));
	}
	
	private function onUserDisconnect(userDisconnectCallback:Int -> Int -> Int -> Void, joint_nr:Int, command_chunk:Bytes):Void
	{
		userDisconnectCallback(joint_nr,  command_chunk.get(0),  command_chunk.get(1));
	}
	
	public function leaveInJoint(joint_nr:Int):Void
	{
		peoteSocket.writeByte(0); // 0 leitet command ein (das waere sonst die chunk-size, die kann aber niemals 1 sein)
		peoteSocket.writeByte(2); // leave command
		peoteSocket.writeByte(0); // (normalerweise die command_nr) 0 -> erwartet keine antwort
		
		peoteSocket.writeByte(1); // chunksize ist 1 da nurnoch joint_nr kommt
		peoteSocket.writeByte(joint_nr); // der eigentliche chunk
		
		peoteSocket.flush();
		
	}
	
	public function deleteOwnJoint(joint_nr:Int):Void
	{
		peoteSocket.writeByte(0); // 0 leitet command ein (das waere sonst die chunk-size, die kann aber niemals 1 sein)
		peoteSocket.writeByte(3); // leave command
		peoteSocket.writeByte(0); // (normalerweise die command_nr) 0 -> erwartet keine antwort
		
		peoteSocket.writeByte(1); // chunksize ist 1 da nurnoch joint_nr kommt
		peoteSocket.writeByte(joint_nr); // der eigentliche chunk
		
		peoteSocket.flush();
		
	}
	
	public function enterInJoint(joint_id:String, commandCallback:Int -> Void,
												dataCallback:Int -> Bytes -> Void,
												disconnectCallback:Int -> Int -> Void,
												errorCallback:Int -> Void = null):Void 
	{
		var bytes:Bytes = Bytes.ofString(joint_id);
		if (bytes.length <= 255)
		{
			var nr:Int = addCommandCallback(255,
							function(command_chunk:Bytes):Void 
							{ onEnterInJoint(command_chunk, commandCallback, dataCallback, disconnectCallback, errorCallback);
							}
			);
			
			if (nr != -1)
			{
				peoteSocket.writeByte(0); // 0 leitet command ein (das waere sonst die chunk-size, die kann aber niemals 1 sein)
				
				peoteSocket.writeByte(1); // enter_in command
				peoteSocket.writeByte(nr); // command nummer fuer die spaetere antwort
				
				// ab hier aber alles fuer die ID in einen kleinen-CHUNK pressen
				peoteSocket.writeByte(bytes.length); // TODO: SICHERSTELLEN das <= 255
				peoteSocket.writeBytes(bytes);
				
				peoteSocket.flush();
			} // TODO: else error for commandCallback overflow
		}
		else
		{
			if (errorCallback != null) errorCallback(-3); // joint_id to long
		}		
	}
	
	private function onEnterInJoint(command_chunk:Bytes, commandCallback:Int -> Void,
															dataCallback:Int -> Bytes -> Void,
															disconnectCallback:Int -> Int -> Void,
															errorCallback:Int -> Void = null):Void 
	{
		
		//trace("enterInJoint(): ANTWORT ...");
		// chunk auswerten:
		if (command_chunk.get(0) == 0) // -> OK 
		{	//trace("OK ----");
			var joint_nr:Int = command_chunk.get(1); // -> joint_nr lesen
			inJointDataCallback.set(joint_nr, dataCallback);
			inDisconnectCallback.set(joint_nr, function(command_chunk:Bytes)
												{ onInDisconnect(disconnectCallback, joint_nr, command_chunk); }
									);
											
			commandCallback(joint_nr);
		}
		else
		{	// FEHLER
			if (errorCallback != null) errorCallback(command_chunk.get(1));
		}
	}
	
	private function onInDisconnect(disconnectCallback:Int -> Int -> Void, joint_nr:Int, command_chunk:Bytes):Void
	{
		inJointDataCallback.remove(joint_nr);
		disconnectCallback(joint_nr, command_chunk.get(2));
	}

	private function onData(bytes:Bytes):Void
	{			
		// zuerst den verbliebenen unverarbeiteten input mit den neuen socket-daten ergaenzen
		if (input_pos == input_end) { input_pos = input_end = 0; }
		
		input.blit(input_pos, bytes, 0, bytes.length );
		
		input_end += bytes.length;
		
		var command_nr:Int=0;
		var server_command:Int=0;
		var j_nr:Int=0;
		
		var weitermachen:Bool = true;
		
		while (input_end > input_pos && weitermachen)
		{
			
			if (command_mode)
			{
				if (input_end - input_pos >= bytes_left) // wenn chunk vollstaendig gelesen wurde
				{	
					// zuerst die nr fuer entsprechenden callback
					command_nr = input.get(input_pos++);
					
					trace("CONTROL COMMAND " + command_nr + " bytes_left="+bytes_left);
						
					if (command_nr > 0) // dann eine ANTWORT auf ein gesendetes Command
					{	
						// -1 weil ja schon command_nr gelesen wurde
						var command_chunk:Bytes = Bytes.alloc(bytes_left - 1);						
						command_chunk.blit(0, input, input_pos, bytes_left - 1 );
						input_pos += (bytes_left - 1);
						
						//command_chunk.position=0;
						waitingCommandCallbacks.get(command_nr)(command_chunk);
						waitingCommandCallbacks.remove(command_nr);
					}
					else // ein Command vom Server (keine Antwort)
					{
						// command auswerten
						server_command = input.get(input_pos++);
						
						// joint_nr auf den sich das command bezieht
						j_nr = input.get(input_pos++);
						
						// -3 weil ja schon command_nr,server_command und j_nr gelesen wurde
						var command_chunk:Bytes = Bytes.alloc(bytes_left - 3);
						command_chunk.blit(0, input, input_pos, bytes_left - 3 );
						input_pos += (bytes_left - 3);
						
						if (server_command == 0) 
						{	
							ownUserConnectCallback.get(j_nr)(command_chunk);
						}
						else if (server_command == 1)
						{
							ownUserDisconnectCallback.get(j_nr)(command_chunk);
						}
						else if (server_command == 2)
						{
							inDisconnectCallback.get(j_nr)(command_chunk);
						}
						//else if (server_command == 255)// keepalive
						//else trace("ERROR: no valid servercommand"); // TODO
					}
					
					command_mode = false;
					bytes_left = 0;
				}
				else
				{
					weitermachen = false;
				}
			}
			else if (bytes_left == 0) // --- neue Chunk-Size noch NICHT uebermittelt  ------
			{
				joint_nr = -1; // neuer chunk, also erstmal joint_nr auf -1 setzen
				user_nr = -1; // neuer chunk, also erstmal user_nr auf -1 setzen
				
				if (input_end - input_pos >= 2 )
				{
					// chunk size erstes byte laden
					var size_1:Int=0; 
					var size_2:Int=0;
					
					size_1 = input.get(input_pos++);
					
					//trace("INPUT: size_1=" + size_1);
					
					if (size_1 < 128) // kleiner chunk
					{
						// TODO: wenn die size == 1 ist, kann dies VORKOMMEN?
						// evtl. nun special-case, also dann ist es ein
						// COMMAND vom SERVER, z.b. wenn neuer joint eroeffnet wurde!!!
						
						if (size_1 == 0) // oder CONTROL COMMAND ANTWORT ------------------
						{	
							// commands immer nur mit kleinem chunk
							bytes_left = input.get(input_pos++);
							command_mode = true;
						}
						else // kleiner chunk
						{
							bytes_left = size_1;
						}
						
					}
					else // grosser Chunk!
					{
						size_2 = input.get(input_pos++);
						bytes_left = (size_1 - 128) * 256 + size_2;
						//trace("GROSSER CHUNK: bytes_left=" + bytes_left);
					}
					
					//trace("ChunkSize:"+bytes_left);
					
				}
				else
				{	// es fehlt noch mehr um ueberhaupt erst loszulegen, also 
					weitermachen = false;
				}
				
				
			}
			else // -------------- Chunk-Size ist uebermittelt  -------------------
			{	
				//trace("bytes_left=" + bytes_left);
				if (joint_nr == -1) // joint_nr wurde noch nicht uebermittelt
				{
					if (input_end - input_pos >= 1) // grab joint_nr ----------
					{
						joint_nr = input.get(input_pos++);
						bytes_left--;
						//trace("joint_nr ist ermittelt :"+joint_nr);
					} else trace("joint_nr cant be get now - bytesAvailable:"+(input_end - input_pos));
					
				}
				else // chunk-size UND joint_nr wurden uebermittelt
				{
					
					if (joint_nr >= 128) // Daten an OWN JOINT --------------
					{
						if (user_nr == -1) // user_nr noch nicht uebermittelt
						{
							if (input_end - input_pos >= 1)
							{
								user_nr = input.get(input_pos++);
								bytes_left--;
								//trace("user_nr ist ermittelt :"+user_nr);
							}
						}
						else // user_nr ist uebermittelt
						{
							
							var avail:Int = input_end - input_pos;
							if (avail >= bytes_left) // wenn chunk schon vollstaendig da ist
							{	
								var data_chunk:Bytes = Bytes.alloc(bytes_left);
								data_chunk.blit(0, input, input_pos, bytes_left );
								input_pos += bytes_left;
								
								ownJointDataCallback.get(joint_nr - 128)(joint_nr-128, user_nr, data_chunk);
								bytes_left = 0;
							}
							else // chunk abziehen und ausgeben was bereits vorhanden ist
							{
								var data_chunk:Bytes = Bytes.alloc(avail);
								data_chunk.blit(0, input, input_pos, avail );
								input_pos += avail;
								
								ownJointDataCallback.get(joint_nr - 128)(joint_nr-128, user_nr, data_chunk);
								bytes_left -= avail;
							}
							//trace("Data OWN: left="+bytes_left);
							
						}
						
						
					}
					else  // Daten an IN JOINT -----------------------------
					{
						var avail:Int = input_end - input_pos;
						if (avail >= bytes_left) // wenn chunk schon vollstaendig da ist
						{	//trace("Daten an IN JOINT : chunk vollstaendig geladen");							
							var data_chunk:Bytes = Bytes.alloc(bytes_left);
							data_chunk.blit(0, input, input_pos, bytes_left );
							input_pos += bytes_left;
							
							inJointDataCallback.get(joint_nr)(joint_nr, data_chunk);  // TODO: CHECK korrekt joint_nr !?
							bytes_left = 0;
						}
						else // chunk abziehen und ausgeben was bereits vorhanden ist
						{	//trace("Daten an IN JOINT : chunk "+avail+" bytes geladen");
							var data_chunk:Bytes = Bytes.alloc(avail);
							data_chunk.blit(0, input, input_pos, avail );
							input_pos += avail;
								
							inJointDataCallback.get(joint_nr)(joint_nr, data_chunk);
							bytes_left -= avail;
						}
						//trace("Data IN: left="+bytes_left);
						
					}
					
					
				}
				
			}
			
			
		} // end while
	
	}
	

	public function sendStringToJointIn(joint_nr:Int, msg:String):Void
	{
		sendDataToJointIn(joint_nr, Bytes.ofString(msg));
	}
	
	public function sendDataToJointIn(joint_nr:Int, ba:Bytes):Void
	{	
		if (ba.length <= 32767 - 2)
		{
			writeChunkSize(ba.length+1);
			peoteSocket.writeByte(joint_nr);
			peoteSocket.writeBytes(ba);
			peoteSocket.flush();
		}
		else
		{
			var pos:Int = 0;
			var len:Int;
			while (pos < ba.length)
			{	
				len =  (ba.length - pos < 32767 - 2) ? ba.length - pos : 32767 - 2;
				
				writeChunkSize(len+1);
				peoteSocket.writeByte(joint_nr);
				writeFullBytes(ba, pos, len);
				peoteSocket.flush();
				
				pos += len;
			}
		}
	}
	
	public function sendStringToJointOwn(joint_nr:Int, user_nr:Int, msg:String):Void
	{
		sendDataToJointOwn(joint_nr, user_nr, Bytes.ofString(msg));
	}
	
	public function sendDataToJointOwn(joint_nr:Int, user_nr:Int, ba:Bytes):Void
	{
		if (ba.length <= 32767 - 2)
		{
			writeChunkSize(ba.length+2);
			peoteSocket.writeByte(joint_nr+128);
			peoteSocket.writeByte(user_nr);
			peoteSocket.writeBytes(ba);
			peoteSocket.flush();
		}
		else
		{
			var pos:Int = 0;
			var len:Int;
			while (pos < ba.length)
			{	
				len =  (ba.length - pos < 32767 - 2) ? ba.length - pos : 32767 - 2;
				
				writeChunkSize(len+2);
				peoteSocket.writeByte(joint_nr + 128);
				peoteSocket.writeByte(user_nr);
				writeFullBytes(ba, pos, len);
				peoteSocket.flush();
				
				pos += len;
			}
			
		}
	}
	
	public function sendChunk(bytes:Bytes):Void 
	{
		writeChunkSize(bytes.length);
		peoteSocket.writeBytes(bytes);
		peoteSocket.flush();
	}
	
	public function writeChunkSize(chunk_size:Int):Void
	{
		// TODO: chunk_size darf max 32767 sein 
		// grosser oder kleiner chunk
		if (chunk_size < 128)
		{
			peoteSocket.writeByte(chunk_size);
		}
		else
		{
			peoteSocket.writeByte( (chunk_size>>8)+128 );
			peoteSocket.writeByte(  chunk_size & 255 );
		}		
	}
	
	public function writeFullBytes(bytes:Bytes, pos:Int, len:Int):Void
	{
		#if js
		//TODO: for flash to optimize? )
		var part:Bytes = Bytes.alloc(len);
		part.blit(0, bytes, pos, len );
		peoteSocket.writeBytes(part);
		#else
		peoteSocket.writeFullBytes(bytes,pos,len);
		#end
	}
}
