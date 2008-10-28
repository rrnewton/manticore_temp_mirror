signature COMPILER = sig
  val languageName : string
  val mkCmd        : {infile:string, outfile:string} -> string
  val ballast      : {infile:string, outfile:string} -> string list  
end
