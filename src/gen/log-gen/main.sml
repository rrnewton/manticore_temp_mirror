(* main.sml
 *
 * COPYRIGHT (c) 2008 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 *
 * @configure_input@
 *)

structure Main : sig

    val main : (string * string list) -> OS.Process.status

  end = struct

    structure P = OS.Path

    structure GenInlineLogH = GeneratorFn (GenInlineLogH)
    structure GenLogEventsDef = GeneratorFn (GenLogEventsDef)
    structure GenLogEventsH = GeneratorFn (GenLogEventsH)

    val rootDir = "@MANTICORE_ROOT@"
    val templateDir = "@MANTICORE_ROOT@/src/gen/log-gen/templates"
    val jsonFile = "@MANTICORE_ROOT@/src/gen/log-gen/log-events.json"

    fun mkTarget (template, path, gen) =
	  (P.concat(templateDir, template), P.concat(rootDir, path), gen)

    val targets = List.map mkTarget [
	    (GenInlineLogH.template,   GenInlineLogH.path,   GenInlineLogH.gen),
	    (GenLogEventsDef.template, GenLogEventsDef.path, GenLogEventsDef.gen),
	    (GenLogEventsH.template,   GenLogEventsH.path,   GenLogEventsH.gen)
	  ]

    fun usage () = TextIO.output (TextIO.stdErr, "usage: log-gen [-help] [-clean] [-depend]\n")

    fun main (cmd, args) = let
	  val info = LoadFile.loadFile jsonFile
	(* remove the generated file *)
	  fun cleanOne (_, path, _) = if OS.FileSys.access(path, [])
		then OS.FileSys.remove path
		else ()
	(* output the "make" dependency for the target *)
	  fun genDependOne (template, path, _) = TextIO.print(concat[
		  path, ": ", template, " ", jsonFile, "\n"
		])
	(* generate a file from its template *)
	  fun genOne (template, path, gen) = (
		TextIO.output(TextIO.stdErr, concat[
		    "generating ", path, " from ", template, "\n"
		  ]);
		gen {logSpec = info, template = template, target = path})
	  in
	    case args
	     of ["-clean"] => List.app cleanOne targets
	      | ["-depend"] => List.app genDependOne targets
	      | ["-help"] => usage()
	      | [] => List.app genOne targets
	      | _ => (usage(); OS.Process.exit OS.Process.failure)
	    (* end case *);
	    OS.Process.success
	  end

  end

