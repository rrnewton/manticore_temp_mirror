structure ListSeq = struct
    type 'a seq = 'a list
    val empty = List.nil
    fun singleton s = s :: List.nil
    val null = List.null
    val length = List.length
    val sub = List.nth
    fun concat (x, y) = x @ y
    fun splitAt (ls, i) = (List.take(ls, i+1), List.drop(ls, i+1))
    fun fromList x = x
    fun toList x = x 
    val rev = List.rev
    fun map (f, s) = List.map f s
    fun reduce (oper, unit, s) = List.foldl  oper unit s
    val take = List.take
    val drop = List.drop
    fun cut (s, n) = (List.take (s, n), List.drop (s, n))
    fun filter (f, s) = List.filter f s
  end