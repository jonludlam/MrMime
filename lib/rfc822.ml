(* See RFC 822 § 3.3:

   SPACE       =  <ASCII SP, space>            ; (     40,      32. )
*)
let is_space = (=) ' '

(* See RFC 822 § 3.3:

   CTL         =  <any ASCII control           ; (  0- 37,  0.- 31.)
                   character and DEL>          ; (    177,     127.)
*)
let is_ctl = function
  | '\000' .. '\031' -> true
  | _                -> false

let is_digit = function
  | '0' .. '9' -> true
  | _          -> false

let is_lwsp = function
  | '\x20' | '\x09' -> true
  | _               -> false
