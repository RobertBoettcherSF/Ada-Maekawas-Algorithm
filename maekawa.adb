with Ada.Text_IO; use Ada.Text_IO;
-- src/maekawa.adb
package body Maekawa is

   Debug_Enable : constant Boolean := False;

   procedure Initialize (System : out Maekawa_System) is
   begin
      System.Events.Count := 0;
      for I in Valid_Node_Id loop
         System.Nodes(I).Id := I;
         System.Nodes(I).State := Init;
         System.Nodes(I).Voted := False;
         System.Nodes(I).Voted_For := 0;
         System.Nodes(I).Inquired := False;
         System.Nodes(I).Timestamp := 0;
         System.Nodes(I).Replies_Count := 0;
         System.Nodes(I).Quorum_Size := 0;
         System.Nodes(I).Queue.Count := 0;
      end loop;
   end Initialize;

   -- Variant: Grid-based quorum construction
   procedure Generate_Grid_Quorums (System : in out Maekawa_System) is
      K : constant := 3; -- Sqrt of Max_Nodes (9)
      Row_I, Col_I, Row_J, Col_J : Integer;
      Idx : Natural;
   begin
      for I in Valid_Node_Id loop
         Row_I := (Integer(I) - 1) / K;
         Col_I := (Integer(I) - 1) mod K;
         Idx := 1;
         
         for J in Valid_Node_Id loop
            Row_J := (Integer(J) - 1) / K;
            Col_J := (Integer(J) - 1) mod K;
            
            if Row_I = Row_J or Col_I = Col_J then
               System.Nodes(I).Quorum(Idx) := Node_Id(J);
               Idx := Idx + 1;
            end if;
         end loop;
         System.Nodes(I).Quorum_Size := Idx - 1;
      end loop;
   end Generate_Grid_Quorums;

   function Check_Intersection (System : Maekawa_System; N1, N2 : Valid_Node_Id) return Boolean is
   begin
      for I in 1 .. System.Nodes(N1).Quorum_Size loop
         for J in 1 .. System.Nodes(N2).Quorum_Size loop
            if System.Nodes(N1).Quorum(I) = System.Nodes(N2).Quorum(J) then
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Check_Intersection;

   -- Event Queue Management
   procedure Enqueue_Event (System : in out Maekawa_System; Ev : Event_Type) is
   begin
      if System.Events.Count >= Max_Events then
         raise Capacity_Error with "Event queue full";
      end if;
      System.Events.Count := System.Events.Count + 1;
      System.Events.Items(System.Events.Count) := Ev;
   end Enqueue_Event;

   -- Priority Queue Management for Node Requests (Sorted by Timestamp ASC)
   procedure Enqueue_Request (Q : in out Request_Queue; Item : Queue_Item) is
      Temp : Queue_Item;
   begin
      if Q.Count >= Max_Queue then return; end if;
      Q.Count := Q.Count + 1;
      Q.Items(Q.Count) := Item;
      -- DEBUG: print enqueue info
      if Debug_Enable then
         Put_Line("DEBUG: Enqueue_Request -> New Count = " & Natural'Image(Q.Count));
         Put_Line("DEBUG: Enqueue_Request -> Item.Node = " & Integer'Image(Integer(Item.Node)) & " Item.Timestamp = " & Integer'Image(Item.Timestamp));
      end if;
      
      -- Bubble sort to maintain priority (lower timestamp = higher priority)
      for I in reverse 2 .. Q.Count loop
         if Q.Items(I).Timestamp < Q.Items(I - 1).Timestamp then
            Temp := Q.Items(I);
            Q.Items(I) := Q.Items(I - 1);
            Q.Items(I - 1) := Temp;
         end if;
      end loop;
   end Enqueue_Request;

   procedure Dequeue_Request (Q : in out Request_Queue; Item : out Queue_Item) is
   begin
      if Q.Count = 0 then raise Capacity_Error; end if;
      Item := Q.Items(1);
      for I in 1 .. Q.Count - 1 loop
         Q.Items(I) := Q.Items(I + 1);
      end loop;
      Q.Count := Q.Count - 1;
   end Dequeue_Request;

   procedure Request_CS (System : in out Maekawa_System; Node : Valid_Node_Id; TS : Integer) is
      Rcv : Valid_Node_Id;
   begin
      System.Nodes(Node).State := Requesting;
      System.Nodes(Node).Timestamp := TS;
      -- Count self votes if quorum includes self, and send requests only to other quorum members
      System.Nodes(Node).Replies_Count := 0;
      for I in 1 .. System.Nodes(Node).Quorum_Size loop
         Rcv := Valid_Node_Id(System.Nodes(Node).Quorum(I));
         if Rcv = Node then
            -- Node implicitly counts its own vote but should NOT mark Voted/Voted_For (those represent grants to others)
            System.Nodes(Node).Replies_Count := System.Nodes(Node).Replies_Count + 1;
         else
            Enqueue_Event(System, (Kind      => Msg_Request,
                                   Sender    => Node,
                                   Receiver  => Rcv,
                                   Timestamp => TS));
         end if;
      end loop;
      if Debug_Enable then
         Put_Line("DEBUG: Request_CS - Node " & Integer'Image(Integer(Node)) & " Replies_Count=" & Natural'Image(System.Nodes(Node).Replies_Count) & " Quorum_Size=" & Natural'Image(System.Nodes(Node).Quorum_Size));
      end if;
   end Request_CS;

   procedure Release_CS (System : in out Maekawa_System; Node : Valid_Node_Id) is
      Rcv : Valid_Node_Id;
   begin
      System.Nodes(Node).State := Init;
      -- reset replies count on release so subsequent requests start fresh
      System.Nodes(Node).Replies_Count := 0;
      for I in 1 .. System.Nodes(Node).Quorum_Size loop
         Rcv := Valid_Node_Id(System.Nodes(Node).Quorum(I));
         -- Avoid sending a release to self (handled locally)
         if Rcv /= Node then
            Enqueue_Event(System, (Kind      => Msg_Release,
                                   Sender    => Node,
                                   Receiver  => Rcv,
                                   Timestamp => 0));
         end if;
      end loop;
   end Release_CS;

   procedure Process_All_Events (System : in out Maekawa_System) is
   begin
      while System.Events.Count > 0 loop
         Process_Next_Event (System);
      end loop;
   end Process_All_Events;

   procedure Process_Next_Event (System : in out Maekawa_System) is
      Ev : Event_Type;
   begin
      if System.Events.Count = 0 then return; end if;
      
      Ev := System.Events.Items(1);
      for I in 1 .. System.Events.Count - 1 loop
         System.Events.Items(I) := System.Events.Items(I + 1);
      end loop;
      System.Events.Count := System.Events.Count - 1;

      case Ev.Kind is
         when Msg_Request => Handle_Request(System, Ev.Sender, Ev.Receiver, Ev.Timestamp);
         when Msg_Reply   => Handle_Reply(System, Ev.Sender, Ev.Receiver);
         when Msg_Release => Handle_Release(System, Ev.Sender, Ev.Receiver);
         when Msg_Inquire => Handle_Inquire(System, Ev.Sender, Ev.Receiver);
         when Msg_Fail    => Handle_Fail(System, Ev.Sender, Ev.Receiver);
         when Msg_YIELD   => Handle_Yield(System, Ev.Sender, Ev.Receiver);
      end case;
   end Process_Next_Event;

   -- Deadlock Avoidance Variant: Request Handling
   procedure Handle_Request (System : in out Maekawa_System; Sender, Receiver : Valid_Node_Id; TS : Integer) is
      Voted_Node : Valid_Node_Id;
   begin
      if not System.Nodes(Receiver).Voted then
         System.Nodes(Receiver).Voted := True;
         System.Nodes(Receiver).Voted_For := Node_Id(Sender);
         if Debug_Enable then
            Put_Line("DEBUG: GRANT from Receiver " & Integer'Image(Integer(Receiver)) & " -> Sender " & Integer'Image(Integer(Sender)));
         end if;
         Enqueue_Event(System, (Msg_Reply, Receiver, Sender, 0));
      else
         -- DEBUG: Log enqueueing action in Handle_Request
         if Debug_Enable then
            Put_Line("DEBUG: Handle_Request - Enqueueing Sender " & Integer'Image(Integer(Sender)) & " into Receiver " & Integer'Image(Integer(Receiver)) & " queue with TS " & Integer'Image(TS));
         end if;
         Enqueue_Request(System.Nodes(Receiver).Queue, (Sender, TS));
         
         -- Check priority for deadlock avoidance (lower TS = higher priority)
         Voted_Node := Valid_Node_Id(System.Nodes(Receiver).Voted_For);
         if TS < System.Nodes(Voted_Node).Timestamp then
            if not System.Nodes(Receiver).Inquired then
               System.Nodes(Receiver).Inquired := True;
               Enqueue_Event(System, (Msg_Inquire, Receiver, Voted_Node, 0));
            end if;
         else
            Enqueue_Event(System, (Msg_Fail, Receiver, Sender, 0));
         end if;
      end if;
   end Handle_Request;

   procedure Handle_Reply (System : in out Maekawa_System; Sender, Receiver : Valid_Node_Id) is
   begin
      System.Nodes(Receiver).Replies_Count := System.Nodes(Receiver).Replies_Count + 1;
      if Debug_Enable then
         Put_Line("DEBUG: Handle_Reply - Receiver " & Integer'Image(Integer(Receiver)) & " Replies_Count=" & Natural'Image(System.Nodes(Receiver).Replies_Count) & " Quorum_Size=" & Natural'Image(System.Nodes(Receiver).Quorum_Size));
      end if;
      if System.Nodes(Receiver).Replies_Count = System.Nodes(Receiver).Quorum_Size then
         System.Nodes(Receiver).State := Holding;
      end if;
   end Handle_Reply;

   procedure Handle_Release (System : in out Maekawa_System; Sender, Receiver : Valid_Node_Id) is
      Next_Req : Queue_Item;
   begin
      if System.Nodes(Receiver).Queue.Count > 0 then
         Dequeue_Request(System.Nodes(Receiver).Queue, Next_Req);
         System.Nodes(Receiver).Voted_For := Node_Id(Next_Req.Node);
         System.Nodes(Receiver).Inquired := False;
         -- Ensure voter is marked as having granted a vote
         System.Nodes(Receiver).Voted := True;
         Enqueue_Event(System, (Msg_Reply, Receiver, Next_Req.Node, 0));
      else
         System.Nodes(Receiver).Voted := False;
         System.Nodes(Receiver).Voted_For := 0;
         System.Nodes(Receiver).Inquired := False;
      end if;
   end Handle_Release;

   procedure Handle_Inquire (System : in out Maekawa_System; Sender, Receiver : Valid_Node_Id) is
   begin
      -- Yield if not in CS to prevent deadlocks
      if System.Nodes(Receiver).State = Requesting then
         System.Nodes(Receiver).Replies_Count := System.Nodes(Receiver).Replies_Count - 1;
         Enqueue_Event(System, (Msg_Yield, Receiver, Sender, 0));
      end if;
   end Handle_Inquire;

   procedure Handle_Yield (System : in out Maekawa_System; Sender, Receiver : Valid_Node_Id) is
      Next_Req : Queue_Item;
   begin
      -- Sender = grantee (the node that yielded)
      -- Receiver = voter (the node that had issued the INQUIRE)
      System.Nodes(Receiver).Inquired := False;
      -- Return sender to queue (with its original timestamp)
      if Debug_Enable then
         Put_Line("DEBUG: Handle_Yield - Enqueueing Sender " & Integer'Image(Integer(Sender)) & " into Receiver " & Integer'Image(Integer(Receiver)) & " queue with TS " & Integer'Image(System.Nodes(Sender).Timestamp));
      end if;
      Enqueue_Request(System.Nodes(Receiver).Queue, (Sender, System.Nodes(Sender).Timestamp));
      
      -- Grant vote to highest priority in queue
      Dequeue_Request(System.Nodes(Receiver).Queue, Next_Req);
      System.Nodes(Receiver).Voted_For := Node_Id(Next_Req.Node);
      -- Ensure voter marked as having granted a vote
      System.Nodes(Receiver).Voted := True;
      Enqueue_Event(System, (Msg_Reply, Receiver, Next_Req.Node, 0));
   end Handle_Yield;

   procedure Handle_Fail (System : in out Maekawa_System; Sender, Receiver : Valid_Node_Id) is
   begin
      null; -- Handled via lack of replies; could track fail count in extended variants.
   end Handle_Fail;

end Maekawa;
