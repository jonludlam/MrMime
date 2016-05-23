open BaseLexer
open Rfc822

type month =
  [ `Jan | `Feb | `Mar | `Apr
  | `May | `Jun | `Jul | `Aug
  | `Sep | `Oct | `Nov | `Dec ]

type day =
  [ `Mon | `Tue | `Wed | `Thu
  | `Fri | `Sat | `Sun ]

type tz =
  [ `TZ of int
  | `UT
  | `GMT | `EST | `EDT | `CST | `CDT
  | `MST | `MDT | `PST | `PDT
  | `Military_zone of char ]

type date      = int * month * int
type time      = int * int * int option
type date_time = day option * date * time * tz

type atom    = Rfc822.atom
type word    = Rfc822.word
type phrase  = [ word | `Dot | `WSP | Rfc2047.encoded ] list

type domain  = [ Rfc822.domain | Rfc5321.literal_domain ]
type local   = Rfc822.local
type mailbox = local * domain list
type person  = phrase option * mailbox
type group   = phrase * person list
type address = [ `Group of group | `Person of person ]
type left    = Rfc822.left
type right   = Rfc822.right
type msg_id  = Rfc822.msg_id

type received =
  [ `Domain of domain
  | `Mailbox of mailbox
  | `Word of word ]

type resent =
  [ `ResentDate      of date_time
  | `ResentFrom      of person list
  | `ResentSender    of person
  | `ResentTo        of address list
  | `ResentCc        of address list
  | `ResentBcc       of address list
  | `ResentMessageID of msg_id
  | `ResentReplyTo   of address list ]

type trace =
  [ `Received        of received list * date_time option
  | `ReturnPath      of mailbox option ]

type field =
  [ `From            of person list
  | `Date            of date_time
  | `Sender          of person
  | `ReplyTo         of address list
  | `To              of address list
  | `Cc              of address list
  | `Bcc             of address list
  | `Subject         of phrase
  | `Comments        of phrase
  | `Keywords        of phrase list
  | `MessageID       of msg_id
  | `InReplyTo       of [`Phrase of phrase | `MsgID of msg_id] list
  | `References      of [`Phrase of phrase | `MsgID of msg_id] list
  | `Field           of string * phrase
  | resent
  | trace ]

(* See RFC 5234 § Appendix B.1:

   VCHAR           = %x21-7E              ; visible (printing) characters
*)
let is_vchar = is_vchar

let s_vchar =
  let make a b incr =
    let rec aux acc i =
      if i > b then List.rev acc
      else aux (incr i :: acc) (incr i)
    in
    aux [a] a
  in

  make 0x21 0x7e ((+) 1) |> List.map Char.chr

(* See RFC 5234 § Appendix B.1:

   SP              = %x20
   HTAB            = %x09                 ; horizontal tab
   WSP             = SP / HTAB            ; white space
*)
let s_wsp  = ['\x20'; '\x09']

(* See RFC 5322 § 3.2.3:

   atext           = ALPHA / DIGIT /      ; Printable US-ASCII
                     "!" / "#" /          ;  characters not including
                     "$" / "%" /          ;  specials. Used for atoms.
                     "&" / "'" /
                     "*" / "+" /
                     "-" / "/" /
                     "=" / "?" /
                     "^" / "_" /
                     "`" / "{" /
                     "|" / "}" /
                     "~"
*)
let is_valid_atext text =
  let i = ref 0 in

  while !i < String.length text
        && is_atext (String.get text !i)
  do incr i done;

  !i = String.length text

(* See RFC 5322 § 3.2.3:

   specials        = %x28 / %x29 /        ; Special characters that do
                     "<"  / ">"  /        ;  not appear in atext
                     "["  / "]"  /
                     ":"  / ";"  /
                     "@"  / %x5C /
                     ","  / "."  /
                     DQUOTE

   See RFC 5234 § Appendix B.1:

   DQUOTE          = %x22
                                          ; (Double Quote)
*)
let is_specials = function
  | '(' | ')'
  | '<' | '>'
  | '[' | ']'
  | ':' | ';'
  | '@' | '\\'
  | ',' | '.'
  | '"' -> true
  | chr -> false

(* See RFC 5322 § 3.6.4:

   msg-id          = [CFWS] "<" id-left "@" id-right ">" [CFWS]
*)
let p_msg_id = p_msg_id

(* See RFC 5322 § 3.2.5 & 4.1:

   phrase          = 1*word / obs-phrase
   obs-phrase      = word *(word / "." / CFWS)
*)
let p_phrase p =
  let add_fws has_fws element words =
    if has_fws
    then element :: `WSP :: words
    else element :: words
  in

  (* XXX: remove unused FWS, if we don't remove that, the pretty-printer raise
          an error. May be, we fix that in the pretty-printer but I decide to
          fix that in this place. *)
  let rec trim = function
    | `WSP :: r -> trim r
    | r -> r
  in

  let rec obs words =
    p_cfws
    @ fun has_fws -> cur_chr
    @ function
      | '.' ->
        junk_chr @ obs (add_fws has_fws `Dot words)
      | chr when is_atext chr || is_dquote chr ->
        Rfc2047.p_try_rule
          (fun word -> obs (add_fws has_fws word words))
          p_word
        (* XXX: without RFC 2047
           p_word (fun word -> obs (add_fws has_fws word words)) state *)
      | _ -> p (trim @@ List.rev @@ trim words)
  in

  let rec loop words =
    (* XXX: we catch [p_word] (with its [CFWS] in [p_atom]/[p_quoted_string])
            to determine if we need to switch to [obs] (if we have a '.'),
            or to continue [p_word] *)
    p_cfws
    @ fun has_fws -> cur_chr
    @ function
      | chr when is_atext chr || is_dquote chr ->
        Rfc2047.p_try_rule
          (fun word -> loop (add_fws true word words))
          p_word
        (* XXX: without RFC 2047
           p_word (fun word -> loop (add_fws true word words)) state *)
      | _ -> obs (if has_fws then `WSP :: words else words)
      (* XXX: may be it's '.', so we try to switch to obs *)
  in

  p_fws
  @ fun _ _ ->
    Rfc2047.p_try_rule
      (fun word -> loop [word])
      p_word

(* See RFC 5322 § 4.1:

   obs-utext       = %d0 / obs-NO-WS-CTL / VCHAR
*)
let is_obs_utext = function
  | '\000' -> true
  | chr -> is_obs_no_ws_ctl chr || is_vchar chr

(* XXX: bon là, j'écris en français parce que c'est vraiment de la merde. En
        gros le [obs-unstruct] ou le [unstructured], c'est de la grosse merde
        pour 3 points:

        * le premier, c'est que depuis la RFC 2047, on peut mettre DES
          [encoded-word] dans un [obs-unstruct] ou un [unstructured]. Il faut
          donc decoder ces fragments premièrement. MAIS il faut bien comprendre
          qu'un (ou plusieurs) espace entre 2 [encoded-word] n'a aucune
          signication - en gros avec: '=utf-8?Q?a=    =utf-8?Q?b=', on obtient
          'ab'. SAUF que dans le cas d'un [encoded-word 1*FWS 1*obs-utext]
          l'espace est significatif et ça moment là, tu te dis WTF! Bien
          entendu, les espaces entre deux [1*obs-utext] est tout autant
          signicatif. DONC OUI C'EST DE LA MERDE.

        * MAIS C'EST PAS FINI! Si on regarde bien la règle, cette pute, elle se
          termine pas. OUAIS OUAIS! En vrai, elle se termine après avoir essayer
          le token [FWS], après avoir essayer [*LF] et [*CR], qu'il y est au
          moins un des deux derniers token existant (donc soit 1*LF ou 1*CR) et
          qu'après avoir essayer à nouveau un [FWS] si on a pas de [obs-utext],
          on regarde si on a bien eu un token [FWS] (d'où la nécessité d'avoir
          [has_wsp] et [has_fws] dans la fonction [p_fws]). DONC (OUAIS C'EST LA
          MERDE), si on a bien un token [FWS], on recommence, SINON on termine.

        * ENFIN LE PIRE HEIN PARCE QUE ENCORE C'EST GENTIL! Comme on ESSAYE
          d'avoir un CR* à la fin, IL PEUT ARRIVER (j'ai bien dit il peut mais
          en vrai ça arrive tout le temps) qu'on consomme le CR du token CRLF
          OBLIGATOIRE à chaque ligne. DONC la fonction compile si tu termines
          par un CR ET SI C'EST LE CAS ON ROLLBACK pour récupérer le CR
          OBLIGATOIRE à la fin de ligne.

        DONC CETTE REGLE, C'EST CARREMENT DE LA MERDE ET VOILA POURQUOI CETTE
        FONCTION EST AUSSI COMPLEXE. Merci de votre attention.
*)
let p_obs_unstruct ?(acc = []) p state =
  let compile rlst state =
    let rec aux ?(previous = `None) acc l = match l, previous with
      | (`Encoded _ as enc) :: r, `LWSP ->
        aux ~previous:`Enc (enc :: `WSP :: acc) r
      | (`Encoded _ as enc) :: r, (`ELWSP | `None) ->
        aux ~previous:`Enc (enc :: acc) r
      | `Encoded _ :: r, (`Atom | `Enc)
      | `Atom _ :: r, `Enc ->
        assert false (* XXX: raise error *)
      | (`Atom _ as txt) :: r, (`LWSP | `ELWSP) ->
        aux ~previous:`Atom (txt :: `WSP :: acc) r
      | (`Atom s as txt) :: r, (`None | `Atom) ->
        aux ~previous:`Atom (txt :: acc) r
      | (`LF | `CR | `WSP | `FWS) :: r1 :: r2, (`ELWSP | `Enc) ->
        aux ~previous:`ELWSP acc (r1 :: r2)
      | (`LF | `CR | `WSP | `FWS) :: r1 :: r2, (`LWSP | `Atom) ->
        aux ~previous:`LWSP acc (r1 :: r2)
      | (`LF | `CR | `WSP | `FWS) :: r1 :: r2, `None ->
        aux ~previous:`None acc (r1 :: r2)
      | [ `CR ], _ ->
        roll_back (fun state -> p (List.rev acc) state) "\r" state
      | [ (`LF | `WSP | `FWS) ], _ | [], _ ->
        p (List.rev acc) state
    in

    aux [] (List.rev rlst)
  in

  let rec data acc =
      (Rfc2047.p_encoded_word
       @ fun charset encoding s state -> `Ok ((charset, encoding, s), state))
      / (p_while is_obs_utext
         @ fun ts -> (0 * 0) is_lf
         @ fun lf -> (0 * 0) is_cr
         @ fun cr ->

         let acc' =
           match String.length lf, String.length cr with
           | 0, 0 -> `Atom ts :: acc
           | n, 0 -> `Atom ts :: `LF :: acc
           | 0, n -> `Atom ts :: `CR :: acc
           | _    -> `Atom ts :: `CR :: `LF :: acc
         in

         cur_chr @ function
         | chr when is_obs_utext chr -> data acc'
         | chr -> loop acc')
      @ (fun (charset, encoding, s) ->
         (0 * 0) is_lf
         @ fun lf -> (0 * 0) is_cr
         @ fun cr ->

         let acc' =
           match String.length lf, String.length cr with
           | 0, 0 -> `Encoded (charset, encoding, s) :: acc
           | n, 0 -> `Encoded (charset, encoding, s) :: `LF :: acc
           | 0, n -> `Encoded (charset, encoding, s) :: `CR :: acc
           | _    -> `Encoded (charset, encoding, s) :: `CR :: `LF :: acc
         in

         cur_chr @ function
         | chr when is_obs_utext chr -> data acc'
         | chr -> loop acc')

  and lfcr acc =
    (0 * 0) is_lf
    @ fun lf -> (0 * 0) is_cr
    @ fun cr ->

    let acc' = match String.length lf, String.length cr with
      | 0, 0 -> acc
      | n, 0 -> `LF :: acc
      | 0, n -> `CR :: acc
      | _    -> `CR :: `LF :: acc
    in

    cur_chr @ function
    | chr when is_obs_utext chr -> data acc
    | chr when String.length lf > 0 || String.length cr > 0 ->
      p_fws
      @ (fun has_wsp has_fws ->
         match has_wsp, has_fws with
         | true, true   -> lfcr (`FWS :: acc')
         | true, false  -> lfcr (`WSP :: acc')
         | false, false -> compile acc'
         | _            -> assert false)
    | _ -> compile acc'

  and loop acc =
    p_fws
    @ fun has_wsp has_fws ->
      match has_wsp, has_fws with
      | true, true   -> loop (`FWS :: acc)
      | true, false  -> loop (`WSP :: acc)
      | false, false -> lfcr acc
      | false, true  -> assert false
  in

  loop acc state

let p_unstructured p state =
  let rec loop acc has_wsp has_fws =
    cur_chr
    @ fun chr -> match has_wsp, has_fws, chr with
      | has_wsp, has_fws, chr when is_vchar chr ->
        let adder x =
          if has_fws && has_wsp
          then x :: `FWS :: acc
          else if has_wsp
          then x :: `WSP :: acc
          else x :: acc
        in
        (Rfc2047.p_encoded_word
         @ fun charset encoding s state -> `Ok ((charset, encoding, s), state))
        / (p_while is_vchar
           @ fun s -> p_fws
           @ loop
           @ adder (`Atom s))
        @ (fun (charset, encoding, s) ->
           p_fws
           @ loop
           @ adder (`Encoded (charset, encoding, s)))
      | true, true, _   -> p_obs_unstruct ~acc:(`FWS :: acc) p
      | true, false, _  -> p_obs_unstruct ~acc:(`WSP :: acc) p
      | false, false, _ -> p_obs_unstruct ~acc p
      | false, true, _  -> assert false
    in

  p_fws (loop []) state


(* [CFWS] 2DIGIT [CFWS] *)
let p_cfws_2digit_cfws p =
  p_cfws
  @ fun _ -> (2 * 2) is_digit
  @ fun n -> p_cfws
  @ p (int_of_string n)

(* See RFC 5322 § 4.3:

   obs-hour        = [CFWS] 2DIGIT [CFWS]
   obs-minute      = [CFWS] 2DIGIT [CFWS]
   obs-second      = [CFWS] 2DIGIT [CFWS]
*)
let p_obs_hour p =
  p_cfws_2digit_cfws
  @ fun n _ -> p n

let p_obs_minute p =
  p_cfws_2digit_cfws
  @ fun n _ -> p n

let p_obs_second p =
  p_cfws_2digit_cfws p

(* See RFC 5322 § 3.3:

   hour            = 2DIGIT / obs-hour
   minute          = 2DIGIT / obs-minute
   second          = 2DIGIT / obs-second
*)
let p_2digit_or_obs p =
  p_try is_digit
  @ fun n ->
    if n = 2
    then p_while is_digit
         @ fun n -> p_cfws
         @ p (int_of_string n)
         (* XXX: in this case, it's possible to
                 be in [obs] version, so we try
                 [CFWS] *)
    else p_cfws_2digit_cfws p

let p_hour p =
  p_2digit_or_obs
  @ fun n _ -> p n

let p_minute p =
  p_2digit_or_obs p

let p_second p =
  p_2digit_or_obs p

(* See RFC 5322 § 3.3 & 4.3:

   year            = (FWS 4*DIGIT FWS) / obs-year
   obs-year        = [CFWS] 2*DIGIT [CFWS]
*)
let p_obs_year p =
  (* [CFWS] 2*DIGIT [CFWS] *)
  p_cfws
  @ fun _ -> (2 * 0) is_digit
  @ fun y -> p_cfws
  @ fun _ -> p (int_of_string y)

let p_year has_already_fws p =
  (* (FWS 4*DIGIT FWS) / obs-year *)
  p_fws
  @ fun has_wsp has_fws -> p_try is_digit
  @ fun n ->
    if (has_wsp || has_fws || has_already_fws) && n >= 4
    then p_while is_digit (* TODO: (4 * 0) is_digit *)
         @ fun y -> p_fws
         @ fun has_wsp has_fws ->
           if has_wsp || has_fws
           then p (int_of_string y)
           else fun state -> raise (Error.Error (Error.err_expected ' ' state))
    else p_obs_year p

(* See RFC 5322 § 3.3 & 4.3:

   day             = ([FWS] 1*2DIGIT FWS) / obs-day
   obs-day         = [CFWS] 1*2DIGIT [CFWS]
*)
let p_obs_day p =
  p_cfws
  @ fun _ -> (1 * 2) is_digit
  @ fun d -> p_cfws
  @ fun _ -> p (int_of_string d)

let p_day p =
  p_fws
  @ fun _ _ -> cur_chr
  @ function
    | chr when is_digit chr ->
      (1 * 2) is_digit
      @ fun d -> p_fws
      @ fun has_wsp has_fws ->
        if has_wsp || has_fws
        then p (int_of_string d)
        else fun state -> raise (Error.Error (Error.err_expected ' ' state))
    | chr -> p_obs_day p

(* See RFC 5322 § 3.3:

   month           = "Jan" / "Feb" / "Mar" / "Apr" /
                     "May" / "Jun" / "Jul" / "Aug" /
                     "Sep" / "Oct" / "Nov" / "Dec"
*)
let p_month p =
  (3 * 3) is_alpha
  @ function
    | "Jan" -> p `Jan
    | "Feb" -> p `Feb
    | "Mar" -> p `Mar
    | "Apr" -> p `Apr
    | "May" -> p `May
    | "Jun" -> p `Jun
    | "Jul" -> p `Jul
    | "Aug" -> p `Aug
    | "Sep" -> p `Sep
    | "Oct" -> p `Oct
    | "Nov" -> p `Nov
    | "Dec" -> p `Dec
    | str   -> fun state -> raise (Error.Error (Error.err_unexpected_str str state))

(* See RFC 5322 § 3.3:

   day-name        = "Mon" / "Tue" / "Wed" / "Thu" /
                     "Fri" / "Sat" / "Sun"
*)
let p_day_name p =
  (3 * 3) is_alpha
  @ function
    | "Mon" -> p `Mon
    | "Tue" -> p `Tue
    | "Wed" -> p `Wed
    | "Thu" -> p `Thu
    | "Fri" -> p `Fri
    | "Sat" -> p `Sat
    | "Sun" -> p `Sun
    | str   -> fun state -> raise (Error.Error (Error.err_unexpected_str str state))

(* See RFC 5322 § 3.3 & 4.3:

   day-of-week     = ([FWS] day-name) / obs-day-of-week
   obs-day-of-week = [CFWS] day-name [CFWS]
*)
let p_day_of_week p =
  p_fws
  @ fun _ _ -> cur_chr
  @ function
    | chr when is_alpha chr -> p_day_name p
    | chr ->
     p_cfws
     @ fun _ -> p_day_name
     @ fun day -> p_cfws
     @ fun _ -> p day

(* See RFC 5322 § 3.3;

   date            = day month year
*)
let p_date p =
  p_day
  @ fun d -> p_month
  @ fun m -> p_year false
  @ fun y -> p (d, m, y)

(* See RFC 5322 § 3.3:

   time-of-day     = hour ":" minute [ ":" second ]
*)
let p_time_of_day p =
  p_hour
  @ fun hh -> p_chr ':'
  @ p_minute
  @ fun mm has_fws -> cur_chr
  @ function
    | ':' ->
      p_chr ':'
      @ p_second
      @ fun ss has_fws -> p has_fws (hh, mm, Some ss)
    | chr -> p has_fws (hh, mm, None)

(* See RFC 5322 § 3.3:

   obs-zone        = "UT" / "GMT" /     ; Universal Time
                                        ; North American UT
                                        ; offsets
                     "EST" / "EDT" /    ; Eastern:  - 5/ - 4
                     "CST" / "CDT" /    ; Central:  - 6/ - 5
                     "MST" / "MDT" /    ; Mountain: - 7/ - 6
                     "PST" / "PDT" /    ; Pacific:  - 8/ - 7
                     %d65-73 /          ; Military zones - "A"
                     %d75-90 /          ; through "I" and "K"
                     %d97-105 /         ; through "Z", both
                     %d107-122          ; upper and lower case
*)
let p_obs_zone p =
  cur_chr @ function
  | '\097' .. '\105' as a -> junk_chr @ p (`Military_zone a)
  | '\107' .. '\122' as a -> junk_chr @ p (`Military_zone a)
  | ('\065' .. '\073' | '\075' .. '\090') ->
    (cur_chr
     @ fun a -> junk_chr
     @ cur_chr
     @ fun b -> match a, b with
     | 'G', 'M' -> p_chr 'M' @ p_chr 'T' @ p `GMT
     | 'E', 'S' -> p_chr 'S' @ p_chr 'T' @ p `EST
     | 'E', 'D' -> p_chr 'D' @ p_chr 'T' @ p `EDT
     | 'C', 'S' -> p_chr 'S' @ p_chr 'T' @ p `CST
     | 'C', 'D' -> p_chr 'D' @ p_chr 'T' @ p `CDT
     | 'M', 'S' -> p_chr 'S' @ p_chr 'T' @ p `MST
     | 'M', 'D' -> p_chr 'D' @ p_chr 'T' @ p `MDT
     | 'P', 'S' -> p_chr 'S' @ p_chr 'T' @ p `PST
     | 'P', 'D' -> p_chr 'D' @ p_chr 'T' @ p `PDT
     | 'U', 'T' -> p_chr 'T' @ p `UT
     | chr, _   -> p (`Military_zone chr))
  | chr -> fun state -> raise (Error.Error (Error.err_unexpected chr state))

(* See RFC 5322 § 3.3:

   zone            = (FWS ( "+" / "-" ) 4DIGIT) / obs-zone
*)
let p_zone has_already_fws p =
  p_fws
  @ fun has_wsp has_fws -> cur_chr
  @ fun chr -> match has_already_fws || has_wsp || has_fws, chr with
    | true, '+' ->
      p_chr '+'
      @ (4 * 4) is_digit
      @ fun tz -> p (`TZ (int_of_string tz))
    | true, '-' ->
      p_chr '-'
      @ (4 * 4) is_digit
      @ fun tz -> p (`TZ (- (int_of_string tz)))
    | true, chr when is_digit chr ->
      (4 * 4) is_digit
      @ fun tz -> p (`TZ (int_of_string tz))
    | _ -> p_obs_zone p

(* See RFC 5322 § 3.3:

   time            = time-of-day zone
*)
let p_time p =
  p_time_of_day
  @ fun has_fws (hh, mm, dd) -> p_zone has_fws
  @ fun tz -> p ((hh, mm, dd), tz)

(* See RFC 5322 § 3.3:

   date-time       = [ day-of-week "," ] date time [CFWS]
*)
let p_date_time p =
  let aux day =
    p_date
    @ fun (d, m, y) -> p_time
    @ fun ((hh, mm, ss), tz) -> p_cfws
    @ fun _ -> p (day, (d, m, y), (hh, mm, ss), tz)
  in

  p_fws
  @ fun _ _ -> cur_chr
  @ function
    | chr when is_alpha chr ->
      p_day_of_week
      @ fun day -> p_chr ','
      @ aux (Some day)
    | chr -> aux None

(* See RFC 5322 § 3.4.1 & 4.4:

   dtext           = %d33-90 /            ; Printable US-ASCII
                     %d94-126 /           ;  characters not including
                     obs-dtext            ;  "[", "]", or %x5C
   obs-dtext       = obs-NO-WS-CTL / quoted-pair
*)
let is_dtext = function
  | '\033' .. '\090'
  | '\094' .. '\126' -> true
  | chr -> is_obs_no_ws_ctl chr

let p_dtext p state =
  let rec loop acc =
    cur_chr @ function
    | '\033' .. '\090'
    | '\094' .. '\126' ->
      p_while is_dtext
      @ fun s -> loop (s :: acc)
    | chr when is_obs_no_ws_ctl chr ->
      p_while is_dtext
      @ fun s -> loop (s :: acc)
    | '\\' ->
      p_quoted_pair
      @ fun chr -> loop (String.make 1 chr :: acc)
    | chr -> p (List.rev acc |> String.concat "")
  in

  loop [] state

(* See RFC 5322 § 4.4:

   obs-domain      = atom *("." atom)
*)
let p_obs_domain p =
  let rec loop acc =
    cur_chr @ function
    | '.' -> junk_chr @ p_atom @ fun o -> loop (`Atom o :: acc)
    | chr -> p (List.rev acc)
  in

  p_atom @ fun first -> loop [`Atom first]

(* See RFC 5322 § 4.4:

   obs-group-list  = 1*([CFWS] ",") [CFWS]
*)
let p_obs_group_list p =
  let rec loop () =
    cur_chr @ function
    | ',' -> junk_chr @  p_cfws @ fun _ -> loop ()
    | chr -> p_cfws @ fun _ -> p
  in

  p_cfws
  @ fun _ -> cur_chr
  @ function
    | ',' -> junk_chr @ p_cfws @ fun _ -> loop ()
    | chr -> fun state -> raise (Error.Error (Error.err_expected ',' state))

(* See RFC 5322 § 3.4.1:

  domain-literal   = [CFWS] "[" *([FWS] dtext) [FWS] "]" [CFWS]
*)
let p_domain_literal p =
  let rec loop acc =
    cur_chr @ function
    | ']' ->
      p_chr ']'
      @ p_cfws
      @ fun _ state ->
        Rfc5321.p_address_literal
        (fun d state' ->
         let open Lexer in
         if state'.pos = state'.len
         (* XXX: we use the old state! *)
         then p d state
         (* XXX: we need to verify if we consume all data, in another
                 case, it's an error! *)
         else raise (Error.Error
                     (Error.err_unexpected_str
                      (Bytes.sub state'.buffer state'.pos (state'.len - state'.pos))
                      state')))
        (Lexer.of_string @@ String.concat "" @@ List.rev acc)
    | chr when is_dtext chr || chr = '\\' ->
      p_dtext
      @ fun s -> p_fws
      @ fun _ _ -> loop (s :: acc)
    | chr -> fun state -> raise (Error.Error (Error.err_unexpected chr state))
  in

  p_cfws
  @ fun _ -> cur_chr
  @ function
    | '[' -> p_chr '[' @ p_fws @ fun _ _ -> loop []
    | chr -> fun state -> raise (Error.Error (Error.err_expected '[' state))

(* See RFC 5322 § 3.4.1:

   domain          = dot-atom / domain-literal / obs-domain
*)
let p_domain p =
  let p_obs_domain' p =
    let rec loop acc =
      cur_chr @ function
      | '.' ->
        junk_chr
        @ p_atom
        @ fun o -> loop (`Atom o :: acc)
      | chr -> p (List.rev acc)
    in

    p_cfws @ fun _ -> loop []
  in

  (* XXX: dot-atom, domain-literal or obs-domain start with [CFWS] *)
  p_cfws
  @ fun _ -> cur_chr
  @ function
    (* it's domain-literal *)
    | '[' -> p_domain_literal @ fun d -> p d
    (* it's dot-atom or obs-domain *)
    | chr ->
      p_dot_atom   (* may be we are [CFWS] allowed by obs-domain *)
      @ function
        (* if we have an empty list, we need at least one atom *)
        | [] -> p_obs_domain @ fun domain -> p (`Domain domain)
        (* in other case, we have at least one atom *)
        | l1 -> p_obs_domain' @ fun l2 -> p (`Domain (List.concat [l1; l2]))

(* See RFC 5322 § 3.4.1:

   addr-spec       = local-part "@" domain
*)
let p_addr_spec p =
  p_local_part
  @ fun local_part -> p_chr '@'
  @ p_domain
  @ fun domain -> p (local_part, domain)

(* See RFC 5322 § 4.4:

   obs-domain-list = *(CFWS / ",") "@" domain
                     *("," [CFWS] ["@" domain])
*)
let p_obs_domain_list p =
  (* *("," [CFWS] ["@" domain]) *)
  let rec loop1 acc =
    cur_chr @ function
    | ',' ->
      (junk_chr
       @ p_cfws
       @ fun _ -> cur_chr
       @ function
         | '@' ->
           junk_chr
           @ p_domain
           @ fun domain -> loop1 (domain :: acc)
         | chr -> p (List.rev acc))
    | chr -> p (List.rev acc)
  in

  (* *(CFWS / ",") "@" domain *)
  let rec loop0 () =
    cur_chr @ function
    | ',' -> junk_chr @ p_cfws @ fun _ -> loop0 ()
    | '@' -> junk_chr @ p_domain @ fun domain -> loop1 [domain]
    (* XXX: may be raise an error *)
    | chr -> fun state -> raise (Error.Error (Error.err_unexpected chr state))
  in

  p_cfws @ fun _ -> loop0 ()

let p_obs_route p =
  p_obs_domain_list
  @ fun domains -> p_chr ':'
  @ p domains

(* See RFC 5322 § 4.4:

   obs-angle-addr  = [CFWS] "<" obs-route addr-spec ">" [CFWS]
*)
let p_obs_angle_addr p =
  p_cfws                                       (* [CFWS] *)
  @ fun _ -> p_chr '<'                         (* "<" *)
  @ p_obs_route                                (* obs-route *)
  @ fun domains -> p_addr_spec                 (* addr-spec *)
  @ fun (local_part, domain) -> p_chr '>'      (* ">" *)
  @ p_cfws                                     (* [CFWS] *)
  @ fun _ -> p (local_part, domain :: domains)

(* See RFC 5322 § 3.4:

   angle-addr      = [CFWS] "<" addr-spec ">" [CFWS] /
                     obs-angle-addr
   ---------------------------------------------------
   obs-route       = obs-domain-list ":"
                   = *(CFWS / ",") "@" domain
                     *("," [CFWS] ["@" domain]) ":"
   ---------------------------------------------------
   angle-addr      = [CFWS] "<"
                     ├ *(CFWS / ",") "@" domain
                     │ *("," [CFWS] ["@" domain]) ":"
                     └ local-part "@" domain

                   = [CFWS] "<"
                     ├ *(CFWS / ",") "@" domain
                     │ *("," [CFWS] ["@" domain]) ":"
                     └ (dot-atom / quoted-string /
                        obs-local-part) "@" domain

                   = [CFWS] "<"
                     ├ *(CFWS / ",") "@" domain
                     │ *("," [CFWS] ["@" domain]) ":"
                     └ ('"' / atext) … "@" domain
   --------------------------------------------------
   [CFWS] "<"
   ├ if "," / "@" ─── *(CFWS / ",") ┐
   └ if '"' / atext ─ local-part    ┤
                                    │
   ┌──────────────────── "@" domain ┘
   ├ if we start with local-part    → ">" [CFWS]
   └ if we start with *(CFWS / ",") → *("," [CFWS] ["@" domain]) ":"
                                      addr-spec ">" [CFWS]
   --------------------------------------------------
   And, we have [p_try_rule] to try [addr-spec] firstly and 
   [obs-angle-addr] secondly.

   So, FUCK OFF EMAIL!
*)

let p_angle_addr p =
  let first p =
    p_cfws
    @ fun _ -> p_chr '<'
    @ p_addr_spec
    @ fun (local_part, domain) -> p_chr '>'
    @ p_cfws
    @ fun _ -> p (local_part, [domain])
  in

  (first @ fun data state -> `Ok (data, state))
  / (p_obs_angle_addr p)
  @ p

(* See RFC 5322 § 3.4:

   display-name    = phrase

   XXX: Updated by RFC 2047
*)
let p_display_name p state = p_phrase p state

(* See RFC 5322 § 3.4:

   name-addr       = [display-name] angle-addr
*)
let p_name_addr p =
  p_cfws
  @ fun _ -> cur_chr
  @ function
    | '<' -> p_angle_addr @ fun addr -> p (None, addr)
    | chr ->
      p_display_name
      @ fun name -> p_angle_addr
      @ fun addr -> p (Some name, addr)

(* See RFC 5322 § 3.4:

   mailbox         = name-addr / addr-spec
*)
let p_mailbox p =
  (p_name_addr @ fun name_addr state -> `Ok (name_addr, state))
  / (p_addr_spec @ fun (local_part, domain) -> p (None, (local_part, [domain])))
  @ p

(* See RFC 5322 § 4.4:

   obs-mbox-list   = *([CFWS] ",") mailbox *("," [mailbox / CFWS])
*)
let p_obs_mbox_list p =
  (* *("," [mailbox / CFWS]) *)
  let rec loop1 acc =
    cur_chr @ function
    | ',' ->
      junk_chr
      @ ((p_mailbox @ fun data state -> `Ok (data, state))
         / (p_cfws @ fun _ -> loop1 acc)
         @ (fun mailbox -> loop1 (mailbox :: acc)))
    | chr -> p (List.rev acc)
  in

  (* *([CFWS] ",") *)
  let rec loop0 () =
    cur_chr @ function
    | ',' -> junk_chr @ p_cfws @ fun _ -> loop0 ()
    | chr -> p_mailbox @ fun mailbox -> loop1 [mailbox] (* mailbox *)
  in

  p_cfws @ fun _ -> loop0 ()

(* See RFC 5322 § 3.4:

   mailbox-list    = (mailbox *("," mailbox)) / obs-mbox-list
*)
let p_mailbox_list p =
  (* *("," [mailbox / CFWS]) *)
  let rec obs acc =
    cur_chr @ function
    | ',' ->
      junk_chr
      @ (p_mailbox @ fun data state -> `Ok (data, state))
         / (p_cfws @ fun _ -> obs acc)
         @ (fun mailbox -> obs (mailbox :: acc))
    | chr -> p (List.rev acc)
  in

  (* *("," mailbox) *)
  let rec loop acc =
    cur_chr @ function
    | ',' ->
      junk_chr
      @ p_mailbox @ fun mailbox -> loop (mailbox :: acc)
    | chr -> p_cfws @ fun _ -> obs acc
  in

  p_cfws
  @ fun _ -> cur_chr
  @ function
    | ',' -> p_obs_mbox_list p (* obs-mbox-list *)
    | chr ->
      p_mailbox
      @ fun mailbox -> cur_chr
      @ function
        | ',' -> loop [mailbox]
        | chr -> p_cfws @ fun _ -> obs [mailbox]

(* See RFC 5322 § 3.4:

   group-list      = mailbox-list / CFWS / obs-group-list
*)
let p_group_list p =
  (p_mailbox_list (fun data state -> `Ok (data, state)))
  / ((p_obs_group_list @ fun state -> `Ok ((), state))
     / (p_cfws @ fun _ -> p [])
     @ (fun () -> p []))
  @ (fun data -> p data)

(* See RFC 5322 § 3.4:

   group           = display-name ":" [group-list] ";" [CFWS]
*)
let p_group p =
  p_display_name
  @ fun display_name -> p_chr ':'
  @ cur_chr
  @ function
    | ';' ->
      p_chr ';'
      @ p_cfws
      @ fun _ -> p (display_name, [])
    | chr ->
      p_group_list
      @ fun group -> p_cfws
      @ fun _ -> p_chr ';'
      @ p (display_name, group)

(* See RFC 5322 § 3.4:

   address         = mailbox / group
*)
let p_address p =
  (p_group (fun data state -> `Ok (data, state)))
  / (p_mailbox (fun mailbox -> p (`Person mailbox)))
  @ (fun group state -> p (`Group group) state)

(* See RFC 5322 § 4.4:

   obs-addr-list   = *([CFWS] ",") address *("," [address / CFWS])
*)
let p_obs_addr_list p =
  (* *("," [address / CFWS]) *)
  let rec loop1 acc =
    cur_chr @ function
    | ',' ->
      junk_chr
      @ ((p_address @ fun data state -> `Ok (data, state))
         / (p_cfws @ fun _ -> loop1 acc)
         @ (fun address -> loop1 (address :: acc)))
    | chr -> p (List.rev acc)
  in

  (* *([CFWS] ",") *)
  let rec loop0 () =
    cur_chr @ function
    | ',' -> junk_chr @ p_address @ fun adress -> loop0 ()
    | chr -> p_address @ fun address -> loop1 [address] (* address *)
  in

  p_cfws @ fun _ -> loop0 ()

(* See RFC 5322 § 3.4:

   address-list    = (address *("," address)) / obs-addr-list
*)
let p_address_list p =
  (* *("," [address / CFWS]) *)
  let rec obs acc =
    cur_chr @ function
    | ',' ->
      junk_chr
      @ ((p_address (fun data state -> `Ok (data, state)))
         / (p_cfws (fun _ -> obs acc))
         @ (fun address -> obs (address :: acc)))
    | chr -> p (List.rev acc)
  in

  (* *("," address) *)
  let rec loop acc =
    cur_chr @ function
    | ',' ->
      junk_chr
      @ ((p_address (fun address state -> `Ok (address, state)))
         / (p_cfws (fun _ -> obs acc))
         @ (fun address -> loop (address :: acc)))
      (* p_address (fun address -> loop (address :: acc)) state *)
    | chr -> p_cfws @ fun _ -> obs acc
  in

  p_cfws
  @ fun _ -> cur_chr
  @ function
    | ',' -> p_obs_addr_list p (* obs-addr-list *)
    | chr ->
      p_address
      @ fun address -> cur_chr
      @ function
        | ',' -> loop [address]
        | chr -> p_cfws @ fun _ -> obs [address]

(* See RFC 5322 § 3.6.8:

   ftext           = %d33-57 /          ; Printable US-ASCII
                     %d59-126           ;  characters not including
                                          ;  ":".
*)
let is_ftext = function
  | '\033' .. '\057'
  | '\059' .. '\126' -> true
  | chr -> false

(* See RFC 5322 § 3.6.8:

   field-name      = 1*ftext
*)
let p_field_name p state = (1 * 0) is_ftext p state

(* See RFC 5322 § 4.5.3:

   obs-bcc         = "Bcc" *WSP ":"
                     (address-list / ( *([CFWS] ",") [CFWS])) CRLF
*)
let p_obs_bcc p =
  let rec aux () =
    p_cfws
    @ fun _ -> cur_chr
    @ function
      | ',' -> aux ()
      | chr -> p []
  in

  (p_address_list @ fun l state -> `Ok (l, state))
  / (fun state -> aux () state)
  @ p

(* See RFC 5322 § 3.6.3:

   bcc             = "Bcc:" [address-list / CFWS] CRLF
*)
let p_bcc p =
  (p_address_list @ fun l state -> `Ok (l, state))
  / (p_obs_bcc p)
  @ p

(* phrase / msg-id for:

   references      = "References:" 1*msg-id CRLF
   obs-references  = "References" *WSP ":" *(phrase / msg-id) CRLF
   in-reply-to     = "In-Reply-To:" 1*msg-id CRLF
   obs-in-reply-to = "In-Reply-To" *WSP ":" *(phrase / msg-id) CRLF
*)
let p_phrase_or_msg_id p =
  let rec loop acc =
      (p_msg_id (fun data state -> `Ok (data, state)))
      / ((p_phrase (fun data state -> `Ok (data, state)))
         / (p (List.rev acc))
         @ (fun x -> loop (`Phrase x :: acc)))
      @ (fun x -> loop (`MsgID x :: acc))
  in

  loop []

(* See RFC 5322 § 3.6.7:

   received-token  = word / angle-addr / addr-spec / domain
*)
let p_received_token p =
  let rec loop acc =
    (p_addr_spec @ fun (local, domain) state -> `Ok ((local, [domain]), state))
    / ((p_angle_addr @ fun data state -> `Ok (data, state))
       / ((p_domain @ fun data state -> `Ok (data, state))
          / ((p_word @ fun data state -> `Ok (data, state))
             / (p_cfws @ fun _ -> p (List.rev acc))
             @ (fun data -> loop (`Word data :: acc)))
          @ (fun data -> loop (`Domain data :: acc)))
       @ (fun data -> loop (`Mailbox data :: acc)))
    @ (fun data -> loop (`Mailbox data :: acc))
  in

  loop []

(* See RFC 5322 § 3.6.7:

   received        = "Received:" *received-token ";" date-time CRLF
   obs-received    = "Received" *WSP ":" *received-token CRLF
*)
let p_received p =
  p_received_token
  @ fun l -> cur_chr
  @ function
    | ';' ->
      p_chr ';'
      @ p_date_time
      @ fun date_time -> p (l, Some date_time)
    | chr -> p (l, None)

(* See RFC 5322 § 3.6.7:

   path            = angle-addr / ([CFWS] "<" [CFWS] ">" [CFWS])
*)
let p_path p =
  let common () =
    (p_angle_addr @ fun data state -> `Ok (data, state))
    / (p_cfws
       @ fun _ -> p_chr '<'
       @ p_cfws
       @ fun _ -> p_chr '>'
       @ p_cfws
       @ fun _ -> p None)
    @ (fun addr -> p (Some addr))
  in

  (* XXX: this is hack! in real-world we can have an email without '<' and '>' *)
  (p_addr_spec (fun data state -> `Ok (data, state)))
  / (fun state -> common () state)
  @ (fun (local, domain) -> p (Some (local, [domain])))

(* See RFC 5322 § 4.1:

   obs-phrase-list = [phrase / CFWS] *("," [phrase / CFWS])
*)
let p_obs_phrase_list p =
  let rec loop acc =
    (p_chr ','
     @ p_phrase
     @ fun s state -> `Ok (s, state))
    / (p_cfws
       @ fun _ -> cur_chr
       @ function
         | ',' -> p_chr ',' @ loop acc
         | chr -> p (List.rev acc))
    @ (fun s -> loop (s :: acc))
  in

  p_cfws
  @ fun _ -> p_phrase
  @ fun s -> loop [s]

(* See RFC 5322 § 3.6.5:

   keywords        = "Keywords:" phrase *("," phrase) CRLF
   obs-keywords    = "Keywords" *WSP ":" obs-phrase-list CRLF
*)
let p_keywords p =
  let rec loop p acc =
    p_phrase
    @ fun s -> cur_chr
    @ function
      | ',' -> p_chr ',' @ loop p (s :: acc)
      | chr -> p_obs_phrase_list @ fun l -> p (List.rev (List.concat [acc; l]))
  in

  (p_phrase @ fun s -> loop (fun s state -> `Ok (s, state)) [s])
  / (p_obs_phrase_list p)
  @ p

(* See RFC 5322 § 3.6.8:

   optional-field  = field-name ":" unstructured CRLF
   obs-optional    = field-name *WSP ":" unstructured CRLF
*)
let p_field extend field p state =
  let rule = match String.lowercase field with
    (* See RFC 5322 § 3.6.1 & 4.5.1:

       orig-date       = "Date:" date-time CRLF
       obs-orig-date   = "Date" *WSP ":" date-time CRLF
    *)
    | "date" -> p_date_time @ fun d -> p_crlf @ p (`Date d)
    (* See RFC 5322 § 3.6.2 & 4.5.2:

       from            = "From:" mailbox-list CRLF
       obs-from        = "From" *WSP ":" mailbox-list CRLF
       sender          = "Sender:" mailbox CRLF
       obs-sender      = "Sender" *WSP ":" mailbox CRLF
       reply-to        = "Reply-To:" address-list CRLF
       obs-reply-to    = "Reply-To" *WSP ":" address-list CRLF
    *)
    | "from" -> p_mailbox_list @ fun l -> p_crlf @ p (`From l)
    | "sender" -> p_mailbox @ fun m -> p_crlf @ p (`Sender m)
    | "reply-to" -> p_address_list @ fun l -> p_crlf @ p (`ReplyTo l)
    (* See RFC 5322 § 3.6.3 & 4.5.3:

       to              = "To:" address-list CRLF
       obs-to          = "To" *WSP ":" address-list CRLF
       cc              = "Cc:" address-list CRLF
       obs-cc          = "Cc" *WSP ":" address-list CRLF
       bcc             = "Bcc:" [address-list / CFWS] CRLF
       obs-bcc         = "Bcc" *WSP ":"
                            (address-list / ( *([CFWS] ",") [CFWS])) CRLF
    *)
    | "to" -> p_address_list @ fun l -> p_crlf @ p (`To l)
    | "cc" -> p_address_list @ fun l -> p_crlf @ p (`Cc l)
    | "bcc" -> p_bcc @ fun l -> p_crlf @ p (`Bcc l)
    (* See RFC 5322 § 3.6.4 & 4.5.4:

       message-id      = "Message-ID:" msg-id CRLF
       obs-message-id  = "Message-ID" *WSP ":" msg-id CRLF
       in-reply-to     = "In-Reply-To:" 1*msg-id CRLF
       obs-in-reply-to = "In-Reply-To" *WSP ":" *(phrase / msg-id) CRLF
       references      = "References:" 1*msg-id CRLF
       obs-references  = "References" *WSP ":" *(phrase / msg-id) CRLF
    *)
    | "message-id" -> p_msg_id @ fun m -> p_crlf @ p (`MessageID m)
    | "in-reply-to" -> p_phrase_or_msg_id @ fun l -> p_crlf @ p (`InReplyTo l)
    | "references" -> p_phrase_or_msg_id @ fun l -> p_crlf @ p (`References l)

    (* See RFC 5322 § 3.6.5 & 4.5.5:

       subject         = "Subject:" unstructured CRLF
       obs-subject     = "Subject" *WSP ":" unstructured CRLF
       comments        = "Comments:" unstructured CRLF
       obs-comments    = "Comments" *WSP ":" unstructured CRLF
       keywords        = "Keywords:" phrase *("," phrase) CRLF
       obs-keywords    = "Keywords" *WSP ":" obs-phrase-list CRLF
    *)
    | "subject" -> p_unstructured @ fun s -> p_crlf @ p (`Subject s)
    | "comments" -> p_unstructured @ fun s -> p_crlf @ p (`Comments s)
    | "keywords" -> p_keywords @ fun l -> p_crlf @ p (`Keywords l)

    (* See RFC 5322 § 3.6.6 & 4.5.6:

       resent-date     = "Resent-Date:" date-time CRLF
       obs-resent-date = "Resent-Date" *WSP ":" date-time CRLF
       resent-from     = "Resent-From:" mailbox-list CRLF
       obs-resent-from = "Resent-From" *WSP ":" mailbox-list CRLF
       resent-sender   = "Resent-Sender:" mailbox CRLF
       obs-resent-send = "Resent-Sender" *WSP ":" mailbox CRLF
       resent-to       = "Resent-To:" address-list CRLF
       obs-resent-to   = "Resent-To" *WSP ":" address-list CRLF
       resent-cc       = "Resent-Cc:" address-list CRLF
       obs-resent-cc   = "Resent-Cc" *WSP ":" address-list CRLF
       resent-bcc      = "Resent-Bcc:" [address-list / CFWS] CRLF
       obs-resent-bcc  = "Resent-Bcc" *WSP ":"
                            (address-list / ( *([CFWS] ",") [CFWS])) CRLF
       resent-msg-id   = "Resent-Message-ID:" msg-id CRLF
       obs-resent-mid  = "Resent-Message-ID" *WSP ":" msg-id CRLF
       obs-resent-rply = "Resent-Reply-To" *WSP ":" address-list CRLF
    *)
    | "resent-date" -> p_date_time @ fun d -> p_crlf @ p (`ResentDate d)
    | "resent-from" -> p_mailbox_list @ fun l -> p_crlf @ p (`ResentFrom l)
    | "resent-sender" -> p_mailbox @ fun m -> p_crlf @ p (`ResentSender m)
    | "resent-to" -> p_address_list @ fun l -> p_crlf @ p (`ResentTo l)
    | "resent-cc" -> p_address_list @ fun l -> p_crlf @ p (`ResentCc l)
    | "resent-bcc" -> p_bcc @ fun l -> p_crlf @ p (`ResentBcc l)
    | "resent-message-id" -> p_msg_id @ fun m -> p_crlf @ p (`ResentMessageID m)
    | "resent-reply-to" -> p_address_list @ fun l -> p_crlf @ p (`ResentReplyTo l)
    (* See RFC 5322 § 3.6.7 & 4.5.7:

       trace           = [return]
                         1*received
       return          = "Return-Path:" path CRLF
       received        = "Received:" *received-token ";" date-time CRLF
       obs-return      = "Return-Path" *WSP ":" path CRLF
       obs-received    = "Received" *WSP ":" *received-token CRLF
    *)
    | "received" -> p_received @ fun r -> p_crlf @ p (`Received r)
    | "return-path" -> p_path @ fun a -> p_crlf @ p (`ReturnPath a)
    (* See RFC 5322 § 3.6.8 & 4.5.8:

       optional-field  = field-name ":" unstructured CRLF
       obs-optional    = field-name *WSP ":" unstructured CRLF
    *)
    | field ->
      p_try_rule p
        (p_unstructured @ fun value -> p_crlf @ p (`Field (field, value)))
        (extend field @ fun data state -> `Ok (data, state))
  in

  rule state

let p_header extend p =
  let rec loop acc =
    (p_field_name
     @ fun field -> (0 * 0) is_wsp
     @ fun _ -> p_chr ':'
     @ p_field extend field
     @ fun data state -> `Ok (data, state))
    / (p (List.rev acc))
    @ (fun field -> loop (field :: acc))
  in

  loop []

(* See RFC 5322 § 3.5:

   body            =   ( *( *998text CRLF) *998text) / obs-body
   text            =   %d1-9 /            ; Characters excluding CR
                       %d11 /             ;  and LF
                       %d12 /
                       %d14-127
   obs-body        =   *(( *LF *CR *((%d0 / text) *LF *CR)) / CRLF)

   XXX: if we don't care about the limit (998 characters per line - and it's
        this case in [obs-body]), [body] and [obs-body] accept all input and
        avoid only CRLF rule.
*)
let p_body stop p state =
  let buf = Buffer.create 16 in

  let rec body has_cr state =
    let rec aux = function
      | `Stop state -> p (Buffer.contents buf) state
      | `Read (buf, off, len, k) ->
        `Read (buf, off, len, (fun i -> aux @@ safe k i))
      | #Error.err as err -> err
      | `Continue state ->
        (cur_chr @ function
         | '\n' when has_cr ->
           junk_chr
           @ fun state ->
             Buffer.add_char buf '\n'; (* XXX: Line-break in UNIX system (may be we
                                          can become more configuration) *)
             body false state
         | '\r' when has_cr ->
           junk_chr
           @ fun state ->
             Buffer.add_char buf '\r';
             body true state
         | '\r' ->
           junk_chr @ body true
         | chr ->
           if has_cr then Buffer.add_char buf '\r';
           junk_chr
           @ fun state ->
             Buffer.add_char buf chr;
             body false state)
        state
    in aux @@ safe stop state
  in

  body false state
