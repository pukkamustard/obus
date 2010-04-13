(*
 * oBus_member.mli
 * ---------------
 * Copyright : (c) 2010, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implementation of D-Bus.
 *)

(** D-Bus member descriptions *)

(** D-Bus Methods *)
module Method : sig

  (** D-Bus method description *)

  (** Type of a method description *)
  type ('a, 'b) t = {
    interface : OBus_name.interface;
    member : OBus_name.member;
    i_args : 'a OBus_value.arguments;
    (** Input arguments *)
    o_args : 'b OBus_value.arguments;
    (** Output arguments *)
  }

  (** {6 Creation} *)

  val make :
    interface : OBus_name.interface ->
    member : OBus_name.member ->
    i_args : 'a OBus_value.arguments ->
    o_args : 'b OBus_value.arguments -> ('a, 'b) t

  (** {6 Projections} *)

  val interface : ('a, 'b) t -> OBus_name.interface
  val member : ('a, 'b) t -> OBus_name.member
  val i_args : ('a, 'b) t -> 'a OBus_value.arguments
  val o_args : ('a, 'b) t -> 'b OBus_value.arguments
end

(** D-Bus signals *)
module Signal : sig

  (** D-Bus signal description *)

  (** Type of a signal description *)
  type 'a t = {
    interface : OBus_name.interface;
    member : OBus_name.member;
    args : 'a OBus_value.arguments;
  }

  (** {6 Creation} *)

  val make :
    interface : OBus_name.interface ->
    member : OBus_name.member ->
    args : 'a OBus_value.arguments -> 'a t

  (** {6 Projections} *)

  val interface : 'a t -> OBus_name.interface
  val member : 'a t -> OBus_name.member
  val args : 'a t -> 'a OBus_value.arguments
end

(** D-Bus properties *)
module Property : sig

  (** D-Bus property description *)

  (** Type of access modes *)
  type 'a access =
      private
    | Readable
    | Writable
    | Readable_writable

  val readable : [ `readable ] access
    (** Access mode for readable properties *)

  val writable : [ `writable ] access
    (** Access mode for writable properties *)

  val readable_writable : [ `readable | `writable ] access
    (** Access mode for readable and writable properties *)

  (** Type of a property description *)
  type ('a, 'access) t = {
    interface : OBus_name.interface;
    member : OBus_name.member;
    typ : 'a OBus_value.C.single;
    access : 'access access;
  }

  (** {6 Creation} *)

  val make :
    interface : OBus_name.interface ->
    member : OBus_name.member ->
    typ : 'a OBus_value.C.single ->
    access : 'access access -> ('a, 'access) t

  (** {6 Projections} *)

  val interface : ('a, 'access) t -> OBus_name.interface
  val member : ('a, 'access) t -> OBus_name.member
  val typ : ('a, 'access) t -> 'a OBus_value.C.single
  val access : ('a, 'access) t -> 'access access
end