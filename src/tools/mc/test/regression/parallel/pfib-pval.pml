fun pfib i = (case i
       of 0 => 0
	| 1 => 1
	| n => let
         pval x = pfib(i-1)
         pval y = pfib(i-2)
         in
	      x + y
	 end
      (* end case *));

val n = 25;
val s = itos (pfib(n));

print ("pfib("^itos n^") is " ^ s ^ "\n")