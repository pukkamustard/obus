open Ocamlbuild_plugin
open Command (* no longer needed for OCaml >= 3.10.2 *)

(* these functions are not really officially exported *)
let run_and_read = Ocamlbuild_pack.My_unix.run_and_read
let blank_sep_strings = Ocamlbuild_pack.Lexers.blank_sep_strings

(* this lists all supported packages *)
let find_packages () =
  blank_sep_strings &
    Lexing.from_string &
    run_and_read "ocamlfind list | cut -d' ' -f1"

(* this is supposed to list available syntaxes, but I don't know how to do it. *)
let find_syntaxes () = ["camlp4o"; "camlp4r"]

(* ocamlfind command *)
let ocamlfind x = S[A"ocamlfind"; x]

let myexts () =
  List.map (fun x -> Pathname.basename (Pathname.remove_extension x))
    (blank_sep_strings &
       Lexing.from_string &
       run_and_read "echo syntax/*.ml")

let _ = dispatch begin function
  | Before_options ->

      (* override default commands by ocamlfind ones *)
      Options.ocamlc   := ocamlfind & A"ocamlc";
      Options.ocamlopt := ocamlfind & A"ocamlopt";
      Options.ocamldep := ocamlfind & A"ocamldep";
      Options.ocamldoc := ocamlfind & A"ocamldoc"

  | After_rules ->

      (* When one link an OCaml library/binary/package, one should use -linkpkg *)
      flag ["ocaml"; "link"] & A"-linkpkg";

      (* For each ocamlfind package one inject the -package option when
       * compiling, computing dependencies, generating documentation and
       * linking. *)
      List.iter begin fun pkg ->
        flag ["ocaml"; "compile";  "pkg_"^pkg] & S[A"-package"; A pkg];
        flag ["ocaml"; "ocamldep"; "pkg_"^pkg] & S[A"-package"; A pkg];
        flag ["ocaml"; "doc";      "pkg_"^pkg] & S[A"-package"; A pkg];
        flag ["ocaml"; "link";     "pkg_"^pkg] & S[A"-package"; A pkg];
      end (find_packages ());

      (* Like -package but for extensions syntax. Morover -syntax is useless
       * when linking. *)
      List.iter begin fun syntax ->
        flag ["ocaml"; "compile";  "syntax_"^syntax] & S[A"-syntax"; A syntax];
        flag ["ocaml"; "ocamldep"; "syntax_"^syntax] & S[A"-syntax"; A syntax];
        flag ["ocaml"; "doc";      "syntax_"^syntax] & S[A"-syntax"; A syntax];
      end (find_syntaxes ());

      List.iter begin fun ext ->
        flag ["ocaml"; "pp"; ext] & A("syntax/"^ext^".cmo");
        dep ["ocaml"; "ocamldep"; ext] ["syntax/"^ext^".cmo"];
      end (myexts ());

      (* For samples to find .cmi files *)
      flag ["ocaml"; "compile"; "samples"] & S[A"-I"; A"obus"];
      flag ["ocaml"; "link"; "samples"] (A"obus.cma");
      dep ["ocaml"; "samples"] ["obus.cma"];
  | _ -> ()
end