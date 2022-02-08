
module P = Catapult

let active = lazy (
  match Sys.getenv "TEF" with
  | "1"|"true" -> true | _ -> false
  | exception Not_found -> false
)

let program_start = Mtime_clock.now()

module Make()
  : P.BACKEND
= struct
  let first_ = ref true
  let closed_ = ref false

  let teardown_ oc =
    if not !closed_ then (
      closed_ := true;
      output_char oc ']'; (* close array *)
      flush oc;
      close_out_noerr oc
    )

  let[@inline] get_ts () : float =
    let now = Mtime_clock.now() in
    Mtime.Span.to_us (Mtime.span program_start now)

  (* connection to subprocess writing into the file *)
  let oc =
    let oc = open_out_bin "trace.json" in
    output_char oc '[';
    at_exit (fun () -> teardown_ oc);
    oc

  (* flush if it's been a while *)
  let maybe_flush =
    let last_write_ = ref (get_ts()) in
    fun () ->
      let n = get_ts() in
      if n > !last_write_ +. 0.2 then (
        last_write_ := n;
        flush oc;
      )

  let emit_sep_ () =
    if !first_ then (
      first_ := false;
    ) else (
      output_string oc ",\n";
    )

  let emit_duration_event ~name ~start ~end_ () : unit =
    let dur = end_ -. start in
    let ts = start in
    let pid = Unix.getpid() in
    let tid = Thread.id (Thread.self()) in
    emit_sep_();
    Printf.fprintf oc
      {json|{"pid": %d,"cat":"","tid": %d,"dur": %.2f,"ts": %.2f,"name":"%s","ph":"X"}|json}
      pid tid dur ts name;
    maybe_flush();
    ()

  let emit_instant_event ~name ~ts () : unit =
    let pid = Unix.getpid() in
    let tid = Thread.id (Thread.self()) in
    emit_sep_();
    Printf.fprintf oc
      {json|{"pid": %d,"cat":"","tid": %d,"ts": %.2f,"name":"%s","ph":"I"}|json}
      pid tid ts name;
    maybe_flush();
    ()

  let teardown () = teardown_ oc
end

let setup_ = lazy (
  let lazy active = active in
  let b = if active then Some (module Make() : P.BACKEND) else None in
  P.Tracing.Control.setup b
)

let setup () = Lazy.force setup_
let teardown = P.Tracing.Control.teardown

let[@inline] with_setup f =
  setup();
  try let x = f() in teardown(); x
  with e -> teardown(); raise e
