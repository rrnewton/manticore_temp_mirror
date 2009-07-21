(* gen-inline-log-h.sml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * Generate the "inline-log.h" file.
 *)

structure GenInlineLogH : GENERATOR =
  struct

    structure Sig = EventSig
    structure Map = Sig.Map

    val template = "inline-log_h.in"
    val path = "src/lib/parallel-rt/include/inline-log.h"

  (* generate the inline logging function for a given signature *)
    fun genForSig outS (sign, {isSource, args}) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	(* generate params for the event arguments *)
	  fun genParams ([], _)= ()
	    | genParams ((_, ty)::r, i) = let
		fun next cty = (
		      prl [", ", cty, "a", Int.toString i];
		      genParams (r, i+1))
		in
		  case ty
		   of Sig.ADDR => next "void *"
		    | Sig.INT => next "int32_t "
		    | Sig.WORD => next "uint32_t "
		    | Sig.FLOAT => next "float "
		    | Sig.DOUBLE => next "double "
		    | Sig.EVENT_ID => next "uint64_t "
		    | Sig.NEW_ID => (* this value is generated by logging function *)
			genParams (r, i+1)
		    | Sig.STR _ => next "const char *"
		  (* end case *)
		end
	(* generate code to copy the event arguments into the event structure *)
	  fun genCopy ([], _) = ()
	    | genCopy ((loc, ty)::r, i) = let
		val param = "a" ^ Int.toString i
		val loc = loc - Sig.argStart
		val index = Word.fmt StringCvt.DEC (Word.>>(loc, 0w2))
		in
		  pr "    ";
		  case ty
		   of Sig.ADDR => prl[
			  "*((void **)&ep->data[", index, "]) = ", param, ";\n"
			]
		    | Sig.INT => prl["ep->data[", index, "] = (uint32_t)", param, ";\n"]
		    | Sig.WORD => prl["ep->data[", index, "] = ", param, ";\n"]
		    | Sig.FLOAT => prl[
			  "*((float *)&ep->data[", index, "]) = ", param, ";\n"
			]
		    | Sig.DOUBLE => prl[
			  "*((double *)&ep->data[", index, "]) = ", param, ";\n"
			]
		    | Sig.EVENT_ID => prl[
			  "*((uint64_t *)&ep->data[", index, "]) = ", param, ";\n"
			]
		    | Sig.NEW_ID => prl[
			  "uint64_t newId = NewEventId(vp);\n",
			  "    *((uint64_t *)&ep->data[", index, "]) = newId;\n"
			]
		    | Sig.STR n => prl[
			  "memcpy (((char *)(ep->data)) + ", Word.fmt StringCvt.DEC loc, ", ",
			  param, ", ", Int.toString n, ");\n"
			]
		  (* end case *);
		  genCopy (r, i+1)
		end
	  in
	    prl [
		"STATIC_INLINE ",
		if isSource then "uint64_t" else "void",
		" LogEvent", sign, " (VProc_t *vp, uint32_t evt"
	      ];
	    genParams (args, 0);
	    pr "\
	      \)\n\
	      \{\n\
	      \    LogEvent_t *ep = NextLogEvent(vp);\n\
	      \\n\
	      \    LogTimestamp (&(ep->timestamp));\n\
	      \    ep->event = evt;\n";
	    genCopy (args, 0);
	    if isSource
	      then pr "    return newId;\n"
	      else ();
	    pr "\n}\n\n"
	  end

  (* generate an event-specific logging macro *)
    fun genLogMacro outS (LoadFile.EVT{id=0, ...}) = ()
      | genLogMacro outS (LoadFile.EVT ed) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	  fun prParams [] = ()
	    | prParams ((a : Sig.arg_desc)::r) = (prl [",", #name a]; prParams r)
	  fun prArgs [] = ()
	    | prArgs ((a : Sig.arg_desc)::r) = (prl [", (", #name a, ")"]; prArgs r)
	(* filter out any new-id arguments *)
	  val args = List.filter (not o Sig.isNewIdArg) (#args ed)
	  in
	    prl ["#define Log", #name ed, "(vp"];
	    prParams args;
	    prl [") LogEvent", #sign ed, " ((vp), ", #name ed, "Evt"];
	    prArgs (Sig.sortArgs args); (* NOTE: location order here! *)
	    pr ")\n"
	  end

  (* generate a dummy logging macro for when logging is disabled *)
    fun genDummyLogMacro outS (LoadFile.EVT{id=0, ...}) = ()
      | genDummyLogMacro outS (LoadFile.EVT ed) = let
	  fun pr s = TextIO.output(outS, s)
	  fun prl l = TextIO.output(outS, concat l)
	  fun prParams [] = ()
	    | prParams ((a : Sig.arg_desc)::r) = (prl [",", #name a]; prParams r)
	  fun prArgs [] = ()
	    | prArgs ((a : Sig.arg_desc)::r) = (prl [", (", #name a, ")"]; prArgs r)
	(* filter out any new-id arguments *)
	  val args = List.filter (not o Sig.isNewIdArg) (#args ed)
	  in
	    prl ["#define Log", #name ed, "(vp"];
	    prParams args;
	    pr ")\n"
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
	(* filter out the PML-only events *)
	  val logDesc = LoadFile.filterEvents (not o (LoadFile.hasAttr LoadFile.ATTR_PML)) logDesc
	  val sigMap = computeSigMap logDesc
	  fun genericLogFuns () = Map.appi (genForSig outS) sigMap
	  fun logFunctions () = LoadFile.applyToEvents (genLogMacro outS) logDesc
	  fun dummyLogFunctions () = LoadFile.applyToEvents (genDummyLogMacro outS) logDesc
	  in [
	    ("GENERIC-LOG-FUNCTIONS", genericLogFuns),
	    ("LOG-FUNCTIONS", logFunctions),
	    ("DUMMY-LOG-FUNCTIONS", dummyLogFunctions)
	  ] end

  end
