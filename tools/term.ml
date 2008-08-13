(*
 * term.ml
 * -------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

module T : sig
  type t =
      private
    | Term of string * t list
    | Tuple of t list
    | Var of string
  val term : string -> t list -> t
  val tuple : t list -> t
  val var : string -> t
end = struct
  type t =
    | Term of string * t list
    | Tuple of t list
    | Var of string
  let term id args = Term(id, args)
  let tuple = function
    | [t] -> t
    | l -> Tuple l
  let var v = Var v
end

include T

open OBus_value

let implem_term_of_basic = function
  | Tbyte -> term "char" []
  | Tboolean -> term "bool" []
  | Tint16 -> term "int16" []
  | Tint32 -> term "int" []
  | Tint64 -> term "int64" []
  | Tuint16 -> term "uint16" []
  | Tuint32 -> term "uint" []
  | Tuint64 -> term "uint64" []
  | Tdouble -> term "float" []
  | Tstring -> term "string" []
  | Tsignature -> term "signature" []
  | Tobject_path -> term "proxy" []

let rec implem_term_of_single = function
  | Tbasic t -> implem_term_of_basic t
  | Tstruct tl -> term "structure" [implem_term_of_sequence tl]
  | Tarray t -> begin match t with
      | Tsingle t ->  term "list" [implem_term_of_single t]
      | Tdict_entry(tk, tv) -> term "assoc" [implem_term_of_basic tk; implem_term_of_single tv]
    end
  | Tvariant -> term "variant" []

and implem_term_of_sequence tl = tuple (List.map implem_term_of_single tl)

let interf_term_of_basic = function
  | Tbyte -> term "char" []
  | Tboolean -> term "bool" []
  | Tint16 -> term "int" []
  | Tint32 -> term "int" []
  | Tint64 -> term "int64" []
  | Tuint16 -> term "int" []
  | Tuint32 -> term "int" []
  | Tuint64 -> term "int64" []
  | Tdouble -> term "float" []
  | Tstring -> term "string" []
  | Tsignature -> term "OBus_types.signature" []
  | Tobject_path -> term "OBus_proxy.t" []

let rec interf_term_of_single = function
  | Tbasic t -> interf_term_of_basic t
  | Tstruct tl -> interf_term_of_sequence tl
  | Tarray t -> term "list" [interf_term_of_element t]
  | Tvariant -> term "OBus_value.single" []

and interf_term_of_element = function
  | Tsingle t -> interf_term_of_single t
  | Tdict_entry(tk, tv) -> tuple [interf_term_of_basic tk; interf_term_of_single tv]

and interf_term_of_sequence tl = tuple (List.map interf_term_of_single tl)

open Format

let rec print_term top pp = function
  | Term(id, []) -> pp_print_string pp id
  | Term(id, [t]) -> fprintf pp "%a %s" (print_term false) t id
  | Term(id, tl) -> fprintf pp "(%a) %s" (print_seq ", ") tl id
  | Var v -> fprintf pp "'%s" v
  | Tuple [] -> pp_print_string pp "unit"
  | Tuple tl -> match top with
      | true -> print_seq " * " pp tl
      | false -> fprintf pp "(%a)" (print_seq " * ") tl

and print_seq sep pp = function
  | [] -> ()
  | [t] -> print_term false pp t
  | t :: tl -> fprintf pp "%a%s%a" (print_term false) t sep (print_seq sep) tl

let rec print_func ret pp = function
  | [] -> print_term true pp ret
  | arg :: args -> fprintf pp "%a -> %a" (print_term true) arg (print_func ret) args