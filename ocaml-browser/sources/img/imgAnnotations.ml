(* CastANet browser - imgAnnotations.ml *)

open Scanf
open Printf
open Morelib

module Aux = struct
    let of_string level data =
        String.split_on_char '\n' data
        |> List.rev_map (String.split_on_char '\t')
        |> List.rev_map (List.map (AmfAnnot.of_string level))
        |> Array.of_list
        |> Array.map Array.of_list

    let to_string data =
        Matrix.map (fun annot -> annot#get) data
        |> Array.map Array.to_list
        |> Array.map (String.concat "\t")
        |> Array.to_list
        |> String.concat "\n"
end



class annotations (assoc : (AmfLevel.t * AmfAnnot.annot Matrix.t) list) = 

object (self)

    method current_level = AmfUI.Levels.current ()
    method current_layer = AmfUI.Layers.current ()

    method get ?level ~r ~c () =
        let level = Option.value level ~default:self#current_level in
        match Matrix.get_opt (List.assoc level assoc) ~r ~c with
        | None -> AmfLog.error ~code:Err.out_of_bounds 
            "ImgAnnotations.annotations#get: Index \
             out of bounds (r = %d, c = %d)" r c
        | Some mask -> mask

    method has_annot ?level ~r ~c () = (self#get ?level ~r ~c ())#has_annot

    method iter level f = Matrix.iteri f (List.assoc level assoc)

    method iter_layer level layer f =
        let has_layer = match layer with
            | '*' -> (fun mask -> String.length mask#get > 0)
            | chr -> (fun mask -> String.contains mask#get chr)
        in
        Matrix.iteri (fun ~r ~c mask ->
            if has_layer mask then f ~r ~c mask
        ) (List.assoc level assoc)

    method statistics level =
        let counters = List.map (fun c -> c, ref 0) (AmfLevel.to_header level) in
        self#iter level (fun ~r ~c mask ->
            String.iter (fun chr -> incr (List.assoc chr counters)) mask#get
        );
        List.map (fun (c, r) -> c, !r) counters

    method to_string level = Aux.to_string (List.assoc level assoc)

end


let filter entries = 
    List.filter (fun e -> 
        Filename.dirname e.Zip.filename = "annotations"
    ) entries


let empty_tables source =
    let r = source#rows and c = source#columns in
    List.map (fun level ->
        level, Matrix.init ~r ~c (fun ~r:_ ~c:_ -> AmfAnnot.create level)
    ) AmfLevel.all_flags


let create ?zip source =
    match zip with
    | None -> new annotations (empty_tables source)
    | Some ich -> let entries = Zip.entries ich in
        match filter entries with
        | [] -> new annotations (empty_tables source)
        | entries ->
            let tables = 
                List.map (fun ({Zip.filename; _} as entry) ->
                    let level = Filename.chop_extension filename
                        |> Filename.basename
                        |> AmfLevel.of_string in
                    let table = Zip.read_entry ich entry
                        |> Aux.of_string level in
                    level, table
                ) entries
            in new annotations tables
