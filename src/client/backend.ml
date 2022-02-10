
module P = Catapult
module Tracing = P.Tracing
module W = Catapult_wire

type event = W.event

module type ARG = sig
  val conn : Connections.t
end

module Make(A : ARG) : P.BACKEND = struct
  let conn = A.conn
  let get_ts = Utils.now_

  let teardown () = Connections.close conn

  let[@inline] opt_map_ f = function
    | None -> None
    | Some x -> Some (f x)

  let conv_arg (key,a) =
    let open W.Ser in
    let value = match a with
      | `Int x -> Arg_value.Arg_value_0 (Int64.of_int x)
      | `String s -> Arg_value.Arg_value_1 s
    in
    {Arg.key; value}

  let emit
      ~id ~name ~ph ~tid ~pid ~cat ~ts_sec ~args ~stack ~dur ?extra () : unit =
    let ev =
      let open W.Ser in
      let tid = Int64.of_int tid in
      let pid = Int64.of_int pid in
      let stack = opt_map_ Array.of_list stack in
      let ph = P.Event_type.to_char ph |> Char.code in
      let cat = opt_map_ Array.of_list cat in
      let extra = match extra with
        | None -> None
        | Some l ->
          Some (Array.of_list l |> Array.map (fun (key,value) -> {Extra.key;value}))
      in
      let args = opt_map_ (fun l -> l |> Array.of_list |> Array.map conv_arg) args in
      {Event.
        id; name; ph; tid; pid; cat; ts_sec; args; stack; dur; extra;
      }
    in
    Connections.send_msg conn ~pid ~now:ts_sec ev
end
