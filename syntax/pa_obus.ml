(*
 * pa_obus.ml
 * ----------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

open Camlp4
open Camlp4.PreCast
open Printf

module Id : Sig.Id = struct
  let name = "Syntactic sugar for obus types"
  let version = "0.1"
end

module Make(Syntax : Sig.Camlp4Syntax) =
struct
  open Sig
  include Syntax

  let rec expr_of_patt = function
    | <:patt@_loc< $int:s$ >> -> <:expr< $int:s$ >> (* integer constant *)
    | <:patt@_loc< $int32:s$ >> -> <:expr< $int32:s$ >>
    | <:patt@_loc< $int64:s$ >> -> <:expr< $int64:s$ >>
    | <:patt@_loc< $nativeint:s$ >> -> <:expr< $nativeint:s$ >>
    | <:patt@_loc< $chr:c$ >> -> <:expr< $chr:c$ >> (* character constant *)
    | <:patt@_loc< $str:s$ >> -> <:expr< $str:s$ >> (* string constant *)
    | <:patt@_loc< $lid:b$ >> -> <:expr< $lid:b$ >> (* local variable *)
    | <:patt@_loc< $uid:b$ >> -> <:expr< $uid:b$ >> (* variable of other module *)
    | <:patt@_loc< ($tup:p$) >> ->                  (* tuple *)
      let e = expr_of_patt p in
        <:expr< ($tup:e$) >>
    | <:patt@_loc< { $r$ } >> ->
      Ast.ExRec(_loc, recbinding_of_patt r, Ast.ExNil _loc)
    | <:patt@_loc< ($e$ : $t$) >> ->                (* type restriction *)
      let p = expr_of_patt e in
        <:expr< ($p$ : $t$) >>
    | p ->
        Loc.raise (Ast.loc_of_patt p)
          (Stream.Error "expr_of_patt: this expression is not yet supported")

  and recbinding_of_patt = function
    | <:patt@_loc< >> -> <:rec_binding< >>
    | <:patt@_loc< $i$ = $p$ >> ->
      let p = expr_of_patt p in
        <:rec_binding< $i$ = $p$ >>
    | <:patt@_loc< $p1$ ; $p2$ >> ->
        let b1 = recbinding_of_patt p1
        and b2 = recbinding_of_patt p2 in
          <:rec_binding< $b1$; $b2$ >>
    | <:patt@_loc< $anti:_$ >> ->
      Loc.raise _loc
        (Stream.Error "recbinding_of_patt: antiquotation are not yet supported")
    | p -> Loc.raise (Ast.loc_of_patt p) (Stream.Error "recbinding_of_patt: not reached")

  (*** Utils ***)

  let abstract args expr =
    List.fold_right (fun arg acc ->
                       let _loc = Ast.loc_of_patt arg in
                       <:expr< fun $arg$ -> $acc$ >>)
      args expr

  let gen_vars l =
    snd (List.fold_left (fun (n, l) e ->
                           (n - 1, (Ast.loc_of_expr e, Printf.sprintf "x%d" n) :: l))
           (List.length l - 1, []) l)

  (***** Big tuple combinator creation *****)

  let make_tuple_type _loc l =
    List.fold_right (fun typ acc ->
                       let _loc = Ast.loc_of_expr typ in
                       <:expr< OBus_value.tpair $typ$ $acc$ >>)
      l <:expr< OBus_value.dunit >>

  let make_tuple_of_seq _loc l =
    let vars = gen_vars l in
    <:expr< fun $ List.fold_right (fun (_loc, var) acc -> <:patt< ($lid:var$, $acc$) >>) vars <:patt< () >> $ ->
              ( $ Ast.exCom_of_list (List.map (fun (_loc, var) -> <:expr< $lid:var$ >>) vars) $ ) >>

  let make_tuple_to_seq _loc l =
    let vars = gen_vars l in
    <:expr< fun $ Ast.PaTup(_loc, Ast.paCom_of_list (List.map (fun (_loc, var) -> <:patt< $lid:var$ >>) vars)) $ ->
      $ List.fold_right (fun (_loc, var) acc -> <:expr< ($lid:var$, $acc$) >>) vars <:expr< () >> $ >>

  (*** Convertion ctyp --> type combinator ***)

  let ty_of_ctyp ctyp =
    let fail loc = Loc.raise loc (Stream.Error "syntax error") in

    let rec parse_id = function
      | <:ident@_loc< $lid:a$ >> -> <:ident< $lid:"t" ^ a$ >>
      | <:ident@_loc< $a$ . $b$ >> -> <:ident< $a$ . $parse_id b$ >>
      | t -> fail (Ast.loc_of_ident t)

    and parse_type = function
      | Ast.TyTup(_loc, t) ->
          let l = List.map parse_type (Ast.list_of_ctyp t []) in
          let count = List.length l in
            if count <= 10
              (* if there is less than 10 type, use a predefined tuple combinator *)
            then List.fold_left (fun acc e -> <:expr< $acc$ $e$ >>) <:expr< $lid:"tup" ^ string_of_int count$ >> l
              (* if there is more, create on a new specific one *)
            else <:expr< OBus_value.wrap_sequence
              $make_tuple_type _loc l$
              $make_tuple_of_seq _loc l$
              $make_tuple_to_seq _loc l$ >>
      | <:ctyp@_loc< '$x$ >> -> <:expr< $lid:x$ >>
      | <:ctyp@_loc< $a$ $b$ >> -> <:expr< $parse_type b$ $parse_type a$ >>
      | <:ctyp@_loc< $id:t$ >> -> <:expr< $id:parse_id t$ >>
      | t -> fail (Ast.loc_of_ctyp t)

    in
      parse_type ctyp

  let rec ty_function_of_ctyp = function
    | <:ctyp@_loc< $a$ -> $b$ >> -> <:expr< OBus_type.abstract $ty_of_ctyp a$ $ty_function_of_ctyp b$ >>
    | t -> let _loc = Ast.loc_of_ctyp t in <:expr< OBus_type.reply $ty_of_ctyp t$ >>

  (***** Bitwise and flag definitions *****)

  type vrn_def =
    | Vrn_classic
    | Vrn_poly

  let make_vrn_expr typ _loc id = match typ with
    | Vrn_classic -> <:expr< $uid:id$ >>
    | Vrn_poly -> Ast.ExVrn(_loc, id)

  let make_vrn_patt typ _loc id = match typ with
    | Vrn_classic -> <:patt< $uid:id$ >>
    | Vrn_poly -> Ast.PaVrn(_loc, id)

  let vrn_type_def _loc typ cstrs = match typ with
    | Vrn_classic -> Ast.sum_type_of_list
        (List.map (fun (p, e, loc, id) -> (loc, id, [])) cstrs)
    | Vrn_poly ->
        Ast.TyVrnEq(_loc, Ast.tyOr_of_list
                      (List.map (fun (p, e, _loc, id) -> <:ctyp< ` $id$ >>) cstrs))

  let make_caml_type_def _loc name vrn_typ cstrs =
    Ast.TyDcl(_loc, name, [], vrn_type_def _loc vrn_typ cstrs, [])

  let invalid_key _loc = Loc.raise _loc (Stream.Error "bitwise keys must be integers")

  let string_of_key = function
    | <:patt@_loc< $int:n$ >> -> n
    | <:patt@_loc< $int32:n$ >> -> n
    | <:patt@_loc< $int64:n$ >> -> n
    | p -> invalid_key (Ast.loc_of_patt p)

  let bw_read = function
    | <:patt@_loc< $int:n$ >> -> <:expr< x land $int:n$ <> 0 >>
    | <:patt@_loc< $int32:n$ >> -> <:expr< Int32.log_and x $int32:n$ <> 0l >>
    | <:patt@_loc< $int64:n$ >> -> <:expr< Int64.log_and x $int64:n$ <> 0L >>
    | p -> invalid_key (Ast.loc_of_patt p)


  let bw_write = function
    | <:expr@_loc< $int:n$ >> -> <:expr< acc lor $int:n$ >>
    | <:expr@_loc< $int32:n$ >> -> <:expr< Int32.log_or acc $int32:n$ >>
    | <:expr@_loc< $int64:n$ >> -> <:expr< Int64.log_or acc $int64:n$ >>
    | e -> invalid_key (Ast.loc_of_expr e)

  let bw_empty = function
    | <:patt@_loc< $int:n$ >> -> <:expr< 0 >>
    | <:patt@_loc< $int32:n$ >> -> <:expr< 0l >>
    | <:patt@_loc< $int64:n$ >> -> <:expr< 0L >>
    | p -> invalid_key (Ast.loc_of_patt p)

  EXTEND Gram
    GLOBAL:expr str_item;

    (*** Parsing of module implementation with obus annotations ***)

    obus_poly_constructor:
      [ [ p = patt; "->"; "`"; id = a_ident ->
            (p, expr_of_patt p, _loc, id)
        ] ];

    obus_constructor:
      [ [ p = patt; "->"; id = a_UIDENT ->
            (p, expr_of_patt p, _loc, id)
        ] ];

    obus_data_type:
      [ [ "["; OPT "|"; l = LIST1 obus_poly_constructor SEP "|"; "]" -> (Vrn_poly, l)
        | OPT "|"; l = LIST1 obus_constructor SEP "|" -> (Vrn_classic, l)
        ] ];

    expr: LEVEL "simple"
      [ [ "[:"; typ = ctyp; "]" -> ty_function_of_ctyp typ ] ];

    str_item:
      [ [ "OBUS_BITWISE"; name = a_LIDENT; "[:"; key_ctyp = ctyp; "]"; "="; (vrntyp, cstrs) = obus_data_type ->
            <:str_item<
              (* First create the caml type definition *)
              type $make_caml_type_def _loc name vrntyp cstrs$

              (* Construct the combinator *)
              let $lid:"t" ^ name ^ "_list"$ = OBus_type.wrap_basic $ty_of_ctyp key_ctyp$
                (fun x ->
                   let l = [] in
                   $ List.fold_left
                       (fun acc (patt, expr, _loc, id) ->
                          <:expr< let l = if $bw_read patt$ then $make_vrn_expr vrntyp _loc id$ :: l else l in $acc$ >>)
                       <:expr< l >> cstrs $)
                (List.fold_left
                   (fun acc x -> match x with
                        $ Ast.mcOr_of_list
                          (List.map (fun (patt, expr, _loc, id) ->
                                       <:match_case< $make_vrn_patt vrntyp _loc id$ -> $bw_write expr$ >>)
                             cstrs) $)
                   $ let (patt, expr, _loc, name) = List.hd cstrs in bw_empty patt $)
            >>

        | "OBUS_FLAG"; name = a_LIDENT; "[:"; key_ctyp = ctyp; "]"; "="; (vrntyp, cstrs) = obus_data_type ->
            <:str_item<
              type $make_caml_type_def _loc name vrntyp cstrs$

              let $lid:"t" ^ name$ = OBus_type.wrap_basic $ty_of_ctyp key_ctyp$
                (function
                     $ Ast.mcOr_of_list
                       ((List.map
                           (fun (patt, expr, _loc, id) ->
                              <:match_case< $patt$ -> $make_vrn_expr vrntyp _loc id$ >>)
                           cstrs) @
                          [ <:match_case< _ -> (failwith $str:"invalid value for " ^ name$ : $lid:name$) >> ]) $)
                (function
                     $ Ast.mcOr_of_list
                       (List.map
                          (fun (patt, expr, _loc, id) ->
                             <:match_case< $make_vrn_patt vrntyp _loc id$ -> $expr$ >>)
                          cstrs) $)
            >>

        | "OBUS_EXN"; name = a_UIDENT; "="; dbus_name = a_STRING ->
            <:str_item<
                exception $uid:name$ of OBus_error.message
                let _ = register_exn $str:dbus_name$
                  (fun msg -> $uid:name$ msg)
                  (function
                     | $uid:name$ msg -> Some msg
                     | _ -> None)
            >>

        | "OBUS_GLOBAL_EXN"; name = a_UIDENT; "="; dbus_name = a_STRING ->
            <:str_item<
                exception $uid:name$ of OBus_error.message
                let _ = OBus_error.register $str:dbus_name$
                  (fun msg -> $uid:name$ msg)
                  (function
                     | $uid:name$ msg -> Some msg
                     | _ -> None)
            >>
        ] ];
  END
end

let module M = Register.OCamlSyntaxExtension(Id)(Make) in ()