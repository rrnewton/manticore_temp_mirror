(* gen-log-events-def.sml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *)

structure GenLogEventsDef : GENERATOR =
  struct

    val template = "log-events_def.in"
    val path = "src/lib/basis/include/log-events.def"

    fun hooks (outS, {date, version, events}) = let
	  fun prl l = TextIO.output(outS, concat l)
	  fun prDef (name, id, desc) = prl [
		  "#define ", name, " ", Int.toString id, " /* ", desc, " */\n"
		]
	  fun genDef ({id = 0, name, desc, ...} : LoadFile.event_desc) = prDef (name, 0, desc)
	    | genDef ({id, name, desc, ...}) = prDef (name^"Evt", id, desc)
	  in [
	    ("LOG-EVENTS", fn () => List.app genDef events)
	  ] end

  end
