type raw              = Rfc2047.raw = QuotedPrintable of string | Base64 of Base64.result
type unstructured     = Rfc5322.unstructured
type phrase_or_msg_id = Rfc5322.phrase_or_msg_id
type field            = [ Rfc5322.field | Rfc5322.skip ]

let pp = Format.fprintf

let pp_lst ~sep pp_data fmt lst =
  let rec aux = function
    | [] -> ()
    | [ x ] -> pp_data fmt x
    | x :: r -> pp fmt "%a%a" pp_data x sep (); aux r
  in aux lst

let pp_raw fmt = function
  | Rfc2047.QuotedPrintable raw -> pp fmt "quoted-printable:%s" raw
  | Rfc2047.Base64 (`Clean raw) -> pp fmt "base64:%s" raw
  | Rfc2047.Base64 (`Dirty raw) -> pp fmt "base64:%S" raw
  | Rfc2047.Base64 `Wrong_padding -> pp fmt "base64:wrong-padding"

let pp_unstructured fmt lst =
  let rec aux fmt = function
    | `Text s -> pp fmt "%s" s
    | `WSP    -> pp fmt "@ "
    | `CR i   -> pp fmt "<cr %d>" i
    | `LF i   -> pp fmt "<lf %d>" i
    | `CRLF   -> pp fmt "<crlf>@\n"
    | `Encoded (charset, raw) ->
      pp fmt "{ @[<hov>charset = %s;@ raw = %a@] }"
        charset pp_raw raw
  in
  pp fmt "@[<hov>%a@]"
    (pp_lst ~sep:(fun fmt () -> pp fmt "@,") aux) lst

let pp_phrase_or_msg_id fmt = function
  | `Phrase p -> pp fmt "%a" Address.pp_phrase p
  | `MsgID m  -> pp fmt "%a" MsgID.pp m

let pp_path = Address.pp_mailbox'
let pp_received fmt r =
  let pp_elem fmt = function
    | `Addr v -> Address.pp_mailbox' fmt v
    | `Domain v -> Address.pp_domain fmt v
    | `Word v -> Address.pp_word fmt v
  in
  match r with
  | (l, Some date) ->
    pp fmt "Received = { @[<hov>%a;@ date = %a@] }"
      (pp_lst ~sep:(fun fmt () -> pp fmt "@ ") pp_elem) l
      Date.pp date
  | (l, None) ->
    pp fmt "Received = @[<hov>%a@]"
      (pp_lst ~sep:(fun fmt () -> pp fmt "@ ") pp_elem) l

let pp_field fmt = function
  | `Date v            -> pp fmt "@[<hov>Date = %a@]" Date.pp v
  | `From v            -> pp fmt "@[<hov>From = @[<v>%a@]@]"
      (pp_lst ~sep:(fun fmt () -> pp fmt ",@ ") Address.pp_mailbox) v
  | `Sender v          -> pp fmt "@[<hov>Sender = %a@]" Address.pp_mailbox v
  | `ReplyTo v         -> pp fmt "@[<hov>Reply-To = %a@]" Address.List.pp v
  | `To v              -> pp fmt "@[<hov>To = %a@]" Address.List.pp v
  | `Cc v              -> pp fmt "@[<hov>Cc = %a@]" Address.List.pp v
  | `Bcc v             -> pp fmt "@[<hov>Bcc = %a@]" Address.List.pp v
  | `MessageID v       -> pp fmt "@[<hov>Message-ID = %a@]" MsgID.pp v
  | `InReplyTo v       -> pp fmt "@[<hov>In-Reply-To = @[<v>%a@]@]"
      (pp_lst ~sep:(fun fmt () -> pp fmt "@\n") pp_phrase_or_msg_id) v
  | `References v      -> pp fmt "@[<hov>References = @[<v>%a@]@]"
      (pp_lst ~sep:(fun fmt () -> pp fmt "@\n") pp_phrase_or_msg_id) v
  | `Subject v         -> pp fmt "@[<hov>Subject = %a@]" pp_unstructured v
  | `Comments v        -> pp fmt "@[<hov>Comments = %a@]" pp_unstructured v
  | `Keywords v        -> pp fmt "@[<hov>Keywords = @[<v>%a@]@]"
      (pp_lst ~sep:(fun fmt () -> pp fmt "@\n") Address.pp_phrase) v
  | `ResentDate v      -> pp fmt "@[<hov>Resent-Date = %a@]" Date.pp v
  | `ResentFrom v      -> pp fmt "@[<hov>Resent-From = @[<v>%a@]@]"
      (pp_lst ~sep:(fun fmt () -> pp fmt ",@ ") Address.pp_mailbox) v
  | `ResentSender v    -> pp fmt "@[<hov>Resent-Sender = %a@]" Address.pp_mailbox v
  | `ResentReplyTo v   -> pp fmt "@[<hov>Resent-Reply-To = %a@]" Address.List.pp v
  | `ResentTo v        -> pp fmt "@[<hov>Resent-To = %a@]" Address.List.pp v
  | `ResentCc v        -> pp fmt "@[<hov>Resent-Cc = %a@]" Address.List.pp v
  | `ResentBcc v       -> pp fmt "@[<hov>Resent-Bcc = %a@]" Address.List.pp v
  | `ResentMessageID v -> pp fmt "@[<hov>Resent-Message-ID = %a@]" MsgID.pp v
  | `Field (k, v)      -> pp fmt "@[<hov>%s = %a@]" (String.capitalize_ascii k) pp_unstructured v
  | `Unsafe (k, v)     -> pp fmt "@[<hov>%s # %a@]" (String.capitalize_ascii k) pp_unstructured v
  | `Trace (Some p, r) ->
    pp fmt "@[<hov>Return-Path = %a@]@\n& %a"
      Trace.pp_path p
      (pp_lst ~sep:(fun fmt () -> pp fmt "@\n& ") Trace.pp_received) r
  | `Trace (None, r)   ->
    pp fmt "%a"
      (pp_lst ~sep:(fun fmt () -> pp fmt "@\n& ") Trace.pp_received) r
  | `Skip line         -> pp fmt "@[<hov># %S@]" line

module Map = Map.Make(String)

type header =
  { date        : Date.date option
  ; from        : Address.mailbox list
  ; sender      : Address.mailbox option
  ; reply_to    : Address.address list
  ; to'         : Address.address list
  ; cc          : Address.address list
  ; bcc         : Address.address list
  ; subject     : unstructured option
  ; msg_id      : MsgID.msg_id option
  ; in_reply_to : phrase_or_msg_id list
  ; references  : phrase_or_msg_id list
  ; comments    : unstructured list
  ; keywords    : Address.phrase list list
  ; resents     : Resent.resent list
  ; traces      : Trace.trace list
  ; fields      : unstructured list Map.t
  ; unsafe      : unstructured list Map.t
  ; skip        : string list }

let default =
  { date        = None
  ; from        = []
  ; sender      = None
  ; reply_to    = []
  ; to'         = []
  ; cc          = []
  ; bcc         = []
  ; subject     = None
  ; msg_id      = None
  ; in_reply_to = []
  ; references  = []
  ; comments    = []
  ; keywords    = []
  ; resents     = []
  ; traces      = []
  ; fields      = Map.empty
  ; unsafe      = Map.empty
  ; skip        = [] }

module Internal =
struct
  open Encoder

  let w_crlf k e = string "\r\n" k e

  let rec w_lst w_sep w_data l =
    let open Wrap in
      let rec aux = function
      | [] -> noop
      | [ x ] -> w_data x
      | x :: r -> w_data x $ w_sep $ aux r
    in aux l

  let w_unstructured _ = Wrap.string "lol"

  let w_field = function
    | `Bcc l ->
      string "Bcc: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_addresses l $ close_box) (unlift k))))
      $ w_crlf
    | `Cc l ->
      string "Cc: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_addresses l $ close_box) (unlift k))))
      $ w_crlf
    | `Subject p ->
      string "Subject:"
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_phrase p $ close_box) (unlift k))))
      $ w_crlf
    | `To l ->
      string "To: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_addresses l $ close_box) (unlift k))))
      $ w_crlf
    | `References l ->
      let w_data = function
        | `Phrase p -> Address.Encoder.w_phrase p
        | `MsgID m -> MsgID.Encoder.w_msg_id m
      in
      string "References: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ w_lst space w_data l $ close_box) (unlift k))))
      $ w_crlf
    | `Field (key, value) ->
      string key $ string ":"
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_phrase value $ close_box) (unlift k))))
      $ w_crlf
    | `Date d ->
      string "Date: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Date.Encoder.w_date d $ close_box) (unlift k))))
      $ w_crlf
    | `InReplyTo l ->
      let w_data = function
        | `Phrase p -> Address.Encoder.w_phrase p
        | `MsgID m -> MsgID.Encoder.w_msg_id m
      in
      string "In-Reply-To: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ w_lst space w_data l $ close_box) (unlift k))))
      $ w_crlf
    | `MessageID m ->
      string "Message-ID: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ MsgID.Encoder.w_msg_id m $ close_box) (unlift k))))
      $ w_crlf
    | `Comments p ->
      string "Comments:"
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_phrase p $ close_box) (unlift k))))
      $ w_crlf
    | `From l ->
      string "From: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ w_lst (string "," $ space) Address.Encoder.w_mailbox l $ close_box) (unlift k))))
      $ w_crlf
    | `Sender p ->
      string "Sender: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_mailbox p $ close_box) (unlift k))))
      $ w_crlf
    | `Unsafe (key, value) ->
      string key $ string ":"
      $ (fun k -> Wrap.(lift ((hovbox 0 $ w_unstructured value $ close_box) (unlift k))))
      $ w_crlf
    | `Keywords l ->
      string "Keywords:"
      $ (fun k -> Wrap.(lift ((hovbox 0 $ w_lst (string "," $ space) Address.Encoder.w_phrase l $ close_box) (unlift k))))
      $ w_crlf
    | `ReplyTo l ->
      string "Reply-To: "
      $ (fun k -> Wrap.(lift ((hovbox 0 $ Address.Encoder.w_addresses l $ close_box) (unlift k))))
      $ w_crlf
end

open Parser

let decoder (fields : [> field ] list) =
  { f = fun i s fail succ ->
    let rec catch garbage acc = function
      | `Date date :: r ->
        catch garbage { acc with date = Some date } r
      | `From lst :: r ->
        catch garbage { acc with from = lst @ acc.from } r
      | `Sender mail :: r ->
        catch garbage { acc with sender = Some mail } r
      | `ReplyTo lst :: r ->
        catch garbage { acc with reply_to = lst @ acc.reply_to } r
      | `To lst :: r ->
        catch garbage { acc with to' = lst @ acc.to' } r
      | `Cc lst :: r ->
        catch garbage { acc with cc = lst @ acc.cc } r
      | `Bcc lst :: r ->
        catch garbage { acc with bcc = lst @ acc.bcc } r
      | `Subject subject :: r ->
        catch garbage { acc with subject = Some subject } r
      | `MessageID msg_id :: r ->
        catch garbage { acc with msg_id = Some msg_id } r
      | `InReplyTo lst :: r->
        catch garbage { acc with in_reply_to = lst @ acc.in_reply_to } r
      | `References lst :: r ->
        catch garbage { acc with references = lst @ acc.references } r
      | `Comments lst :: r ->
        catch garbage { acc with comments = lst :: acc.comments } r
      | `Keywords lst :: r ->
        catch garbage { acc with keywords = lst :: acc.keywords } r
      | `Field (field_name, value) :: r ->
        let fields =
          try let old = Map.find field_name acc.fields in
              Map.add field_name (value :: old) acc.fields
          with Not_found -> Map.add field_name [value] acc.fields
        in
        catch garbage { acc with fields = fields } r
      | `Unsafe (field_name, value) :: r ->
        let unsafe =
          try let old = Map.find field_name acc.unsafe in
              Map.add field_name (value :: old) acc.unsafe
          with Not_found -> Map.add field_name [value] acc.unsafe
        in
        catch garbage { acc with unsafe = unsafe } r
      | `Skip line :: r ->
        catch garbage { acc with skip = line :: acc.skip } r
      | field :: r ->
        catch (field :: garbage) acc r
      | [] -> acc, List.rev garbage (* keep the order *)
    in

    succ i s (catch [] default fields) }
  >>= fun (header, fields) -> Trace.decoder fields
  >>= fun (traces, fields) -> return ({ header with traces = traces }, fields)
  >>= fun (header, fields) -> Resent.decoder fields
  >>= fun (resents, fields) -> return ({ header with resents = resents }, fields)

let of_string ?(chunk = 1024) s =
  let s' = s ^ "\r\n" in
  let l = String.length s' in
  let i = Input.create_bytes chunk in

  let rec aux consumed = function
    | Fail _ -> None
    | Read { buffer; k; } ->
      let n = min chunk (l - consumed) in
      Input.write_string buffer s' consumed n;
      aux (consumed + n) @@ k n (if n = 0 then Complete else Incomplete)
    | Done v -> Some v
  in

  aux 0 @@ run i (Rfc5322.header (fun _ -> fail Rfc5322.Nothing_to_do) >>= decoder <* Rfc822.crlf)

let of_string_raw ?(chunk = 1024) s off len =
  let i = Input.create_bytes chunk in

  let rec aux consumed = function
    | Fail _ -> None
    | Read { buffer; k; } ->
      let n = min chunk (len - (consumed - off)) in
      Input.write_string buffer s consumed n;
      aux (consumed + n) @@ k n (if (consumed + n - off) = len then Complete else Incomplete)
    | Done v -> Some (v, consumed - off)
  in

  aux off @@ run i (Rfc5322.header (fun _ -> fail Rfc5322.Nothing_to_do) >>= decoder)
