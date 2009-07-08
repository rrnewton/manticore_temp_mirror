(* gen-logging-pml.sml
 *
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Generate the "inline-log.h" file.
 *)

structure GenLoggingPML : GENERATOR =
  struct

    structure Sig = EventSig
    structure Map = Sig.Map
    structure F = Format

    val template = "logging_pml.in"
    val path = "src/lib/basis/misc/logging.pml"

  (* filter out "new-id" arguments, since they are generated by the logging code *)
    fun filterArgs (args : Sig.arg_desc list) =
	  List.filter (fn {ty=Sig.NEW_ID, ...} => false | _ => true) args

  (* generate the inline logging function for a given signature *)
    fun genForSig outS (sign, {isSource, args}) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	  fun prf (fmt, l) = TextIO.output(outS, F.format fmt l)
	(* generate params for the event arguments *)
	  fun genParams ([], _)= ()
	    | genParams ((_, ty)::r, i) = let
		fun next cty = (
		      prl [", ", cty, "a", Int.toString i];
		      genParams (r, i+1))
		in
		  case ty
		   of Sig.ADDR => next "any"
		    | Sig.INT => next "int"
		    | Sig.WORD => next "int"
		    | Sig.FLOAT => next "float"
		    | Sig.DOUBLE => next "double"
		    | Sig.EVENT_ID => next "long"
		    | Sig.NEW_ID => (* this value is generated by logging function *)
			genParams (r, i+1)
		    | Sig.STR _ => next "any"
		  (* end case *)
		end
	(* generate code to copy the event arguments into the event structure *)
	  fun genCopy ([], _) = ()
	    | genCopy ((loc, ty)::r, i) = let
		val param = "a" ^ Int.toString i
		val loc = loc - Sig.argStart
		val items = [F.WORD loc, F.STR param]
		in
		  pr "\t    ";
		  case ty
		   of Sig.ADDR => prf("do AdrStoreAdr(AdrAdd32(evt, %d), %s)\n", items)
		    | Sig.INT => prf("do AdrStoreI32(AdrAdd32(evt, %d), %s)\n", items)
		    | Sig.WORD => prf("do AdrStoreI32(AdrAdd32(evt, %d), %s)\n", items)
		    | Sig.FLOAT => prf("do AdrStoreF32(AdrAdd32(evt, %d), %s)\n", items)
		    | Sig.DOUBLE => prf("do AdrStoreF64(AdrAdd32(evt, %d), %s)\n", items)
		    | Sig.EVENT_ID => prf("do AdrStoreI64(AdrAdd32(evt, %d), %s)\n", items)
		    | Sig.NEW_ID => (
			pr "let newId : long = @NewEventId(vp)\n";
			pr "\t    ";
			prf("do AdrStoreI64(AdrAdd32(evt, %d), newId)\n", [F.WORD loc]))
		    | Sig.STR n => ()
		  (* end case *);
		  genCopy (r, i+1)
		end
	  in
	    prl ["\tdefine inline @log-event", sign, " (vp : vproc, evt : int"];
	    genParams (args, 0);
	    prl [") : ", if isSource then "long" else "()", " =\n"];
	    pr "\
	      \\t    let ep : addr(any) = @NextLogEvent(vp)\n\
	      \\t    do @LogTimestamp (ep)\n\
	      \\t    do AdrStoreI32(AdrAdd32(ep, %d), evt)\n\
	      \";
	    genCopy (args, 0);
	    if isSource
	      then pr "\t    return (newId)\n"
	      else pr "\t    return ()\n";
	    pr "\t  ;\n"
	  end

  (* generate an event-specific logging HLOp *)
    fun genLogHLOp outS (evt as LoadFile.EVT ed) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	  val isSource = LoadFile.hasAttr LoadFile.ATTR_SRC evt
	  val retTy = if isSource then "long" else "unit"
	  fun argToBOMTy ({ty, ...} : Sig.arg_desc) = (case ty
		 of Sig.ADDR => "any"
		  | Sig.INT => "int"
		  | Sig.WORD => "int"
		  | Sig.FLOAT => "float"
		  | Sig.DOUBLE => "double"
		  | Sig.NEW_ID => "long"
		  | Sig.EVENT_ID => "long"
		  | Sig.STR n => raise Fail "strings not supported yet"
		(* end case *))
	  val args = filterArgs  (Sig.sortArgs(#args ed))
	  in
	    prl ["\tdefine inline @log-", #name ed, " (vp : vproc"];
	    List.app (fn a => prl [", ", #name a, " : ", argToBOMTy a]) args;
	    prl [") : ", retTy, " = \n"];
	  (* invoke generic HLOp *)
	    if isSource
	      then pr "\t    let id : long = @log-event"
	      else pr "\t    do @log-event";
	    prl [#sign ed, " (vp, ", #name ed, "Evt"];
	    List.app (fn a => prl [", ", #name a]) args;
	    pr ")\n";
	  (* return result (if any) *)
	    if isSource
	      then pr "\t    return (id)\n"
	      else pr "\t    return ()\n";
	    pr "\t  ;\n"
	  end

  (* generate an event-specific logging HLOp that has been wrapped to be called by PML *)
    fun genWrappedLogHLOp outS (evt as LoadFile.EVT ed) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	  val isSource = LoadFile.hasAttr LoadFile.ATTR_SRC evt
	  val retTy = if isSource then "[long]" else "unit"
	  fun argToBOMTy ({ty, ...} : Sig.arg_desc) = (case ty
		 of Sig.ADDR => "any"
		  | Sig.INT => "int"
		  | Sig.WORD => "int"
		  | Sig.FLOAT => "float"
		  | Sig.DOUBLE => "double"
		  | Sig.NEW_ID => "long"
		  | Sig.EVENT_ID => "long"
		  | Sig.STR n => raise Fail "strings not supported yet"
		(* end case *))
	  fun argToWrappedTy ({ty, ...} : Sig.arg_desc) = (case ty
		 of Sig.ADDR => "any"
		  | Sig.INT => "[int]"
		  | Sig.WORD => "[int]"
		  | Sig.FLOAT => "[float]"
		  | Sig.DOUBLE => "[double]"
		  | Sig.NEW_ID => "[long]"
		  | Sig.EVENT_ID => "[long]"
		  | Sig.STR n => raise Fail "strings not supported yet"
		(* end case *))
	  fun isWrapped ({ty, ...} : Sig.arg_desc) = (case ty
		 of Sig.ADDR => false
		  | _ => true
		(* end case *))
	  val args = filterArgs  (Sig.sortArgs(#args ed))
	  in
	    prl ["\tdefine inline @w-log-", #name ed, " ("];
	    case args
	     of [] => pr "_ : unit"
	      | [arg] => prl [#name arg, " : ", argToWrappedTy arg]
	      | arg::rest => (
		  prl ["arg : ["];
		  pr (argToWrappedTy arg);
		  List.app (fn a => prl[", ", argToWrappedTy a]) rest;
		  pr "]")
	    (* end case *);
	    prl [" / _ : exh) : ", retTy, " = \n"];
	  (* unwrapping of arguments *)
	    case args
	     of [] => ()
	      | [arg] => if isWrapped arg
		    then prl [
			"\t    let ", #name arg, " : ", argToBOMTy arg, " = #0(", #name arg, ")\n"
		      ]
		    else ()
	      | args => let
		  fun f (arg, i) = (
			if isWrapped arg
			  then prl [
			      "\t    let ", #name arg, " : ", argToBOMTy arg, " = #0(#",
			      Int.toString i, "(arg))\n"
			    ]
			  else ();
			i+1)
		  in
		    ignore (List.foldl f 0 args)
		  end
	    (* end case *);
	  (* invoke unwrapped HLOp *)
	    if isSource
	      then pr "\t    let id : long = @log-"
	      else pr "\t    do @log-";
	    prl [#name ed, " (host_vproc"];
	    List.app (fn a => prl[", ", #name a]) args;
	    pr ")\n";
	  (* wrap and return result (if any) *)
	    if isSource
	      then (
		pr "\t    let res : [long] = alloc (id)\n";
		pr "\t    return (res)\n")
	      else pr "\t    return (UNIT)\n";
	    pr "\t  ;\n"
	  end

  (* generate a dummy logging macro for when logging is disabled *)
    fun genDummyLogHLOp outS (evt as LoadFile.EVT ed) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	  val isSource = LoadFile.hasAttr LoadFile.ATTR_SRC evt
	  val retTy = if isSource then "long" else "unit"
	  fun argToBOMTy ({ty, ...} : Sig.arg_desc) = (case ty
		 of Sig.ADDR => "any"
		  | Sig.INT => "int"
		  | Sig.WORD => "int"
		  | Sig.FLOAT => "float"
		  | Sig.DOUBLE => "double"
		  | Sig.NEW_ID => "long"
		  | Sig.EVENT_ID => "long"
		  | Sig.STR n => raise Fail "strings not supported yet"
		(* end case *))
	  val args = filterArgs  (Sig.sortArgs(#args ed))
	  in
	    prl ["\tdefine inline @log-", #name ed, " (_ : vproc"];
	    List.app (fn a => prl [", _ : ", argToBOMTy a]) args;
	    prl [") : ", retTy, " = "];
	  (* return result (if any) *)
	    if isSource
	      then pr "return (0 : long);\n"
	      else pr "return ();\n"
	  end

  (* generate an event-specific logging function *)
    fun genLogFun outS (evt as LoadFile.EVT{name, args, ...}) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	  val retTy = if LoadFile.hasAttr LoadFile.ATTR_SRC evt
		then "long"
		else "unit"
	  fun argToTy ({ty, ...} : Sig.arg_desc) = (case ty
		 of Sig.ADDR => "'a"  (* FIXME: what about multiple ADDR args *)
		  | Sig.INT => "int"
		  | Sig.WORD => "int"
		  | Sig.FLOAT => "float"
		  | Sig.DOUBLE => "double"
		  | Sig.NEW_ID => "long"
		  | Sig.EVENT_ID => "long"
		  | Sig.STR n => "string"
		(* end case *))
	  in
	    prl ["    val log", name, " : "];
	    case filterArgs args
	     of [] => pr "unit"
	      | [arg] => pr(argToTy arg)
	      | arg::rest => (
		  prl ["(", argToTy arg];
		  List.app (fn a => prl [" * ", argToTy a]) rest;
		  pr ")")
	    (* end case *);
	    prl [" -> ", retTy, " = _prim (@w-log-", name, ")\n"]
	  end

  (* compute a mapping from signatures to their argument info from the list of event
   * descriptors.
   *)
    fun computeSigMap logDesc = let
	  val isSourceEvt = LoadFile.hasAttr LoadFile.ATTR_SRC
	  fun doEvent (evt as LoadFile.EVT{sign, args, ...}, map) = (case Map.find(map, sign)
		 of SOME _ => map
		  | NONE => let
		      val argInfo = {
			      isSource = isSourceEvt evt,
			      args = List.map (fn {loc, ty, ...} => (loc, ty)) args
			    }
		      in
			Map.insert (map, sign, argInfo)
		      end
		(* end case *))
	  in
	    LoadFile.foldEvents doEvent Map.empty logDesc
	  end

    fun hooks (outS, logDesc : LoadFile.log_file_desc) = let
	(* filter out the runtime-system-only events *)
	  val logDesc = LoadFile.filterEvents (not o (LoadFile.hasAttr LoadFile.ATTR_RT)) logDesc
	  val sigMap = computeSigMap logDesc
	  fun genericLogHLOps () = Map.appi (genForSig outS) sigMap
	  fun logHLOps () = LoadFile.applyToEvents (genLogHLOp outS) logDesc
	  fun wrappedHLOps () = LoadFile.applyToEvents (genWrappedLogHLOp outS) logDesc
	  fun dummyLogHLOps () = LoadFile.applyToEvents (genDummyLogHLOp outS) logDesc
	  fun logFunctions () = LoadFile.applyToEvents (genLogFun outS) logDesc
	  in [
	    ("GENERIC-LOG-HLOPS", genericLogHLOps),
	    ("LOG-HLOPS", logHLOps),
	    ("WRAPPED-LOG-HLOPS", wrappedHLOps),
	    ("DUMMY-LOG-HLOPS", dummyLogHLOps),
	    ("LOG-FUNCTIONS", logFunctions)
	  ] end

  end
