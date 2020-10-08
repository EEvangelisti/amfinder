(* CastANet browser - imgPredictions.ml *)

open Printf
open Morelib


module Aux = struct
    let line_to_assoc r c t =
        String.split_on_char '\t' t
        |> List.map Float.of_string
        |> (fun t -> (r, c), t)

    let of_string data =
        let raw = List.map 
            (fun s ->
                Scanf.sscanf s "%d\t%d\t%[^\n]" line_to_assoc
            ) (List.tl (String.split_on_char '\n' (String.trim data))) in
        let nr = List.fold_left (fun m ((r, _), _) -> max m r) 0 raw + 1
        and nc = List.fold_left (fun m ((_, c), _) -> max m c) 0 raw + 1 in
        let table = Matrix.init nr nc (fun ~r:_ ~c:_ -> []) in  
        List.iter (fun ((r, c), t) -> table.(r).(c) <- t) raw;
        table

    let to_string level table =
        let buf = Buffer.create 100 in
        (* TODO: improve this! *)
        let header = CLevel.to_header level
            |> List.map (String.make 1)
            |> String.concat "\t" in
        bprintf buf "row\tcol\t%s\n" header;
        Matrix.iteri (fun ~r ~c t ->
            List.map Float.to_string t
            |> String.concat "\t"
            |> bprintf buf "%d\t%d\t%s\n" r c
        ) table;
        Buffer.contents buf
end


class predictions input = object (self)

    val mutable curr : string option = None

    method current = curr
    method set_current x = curr <- x
    method active = curr <> None

    method ids level = 
        List.filter (fun (_, (x, _)) -> x = level) input
        |> List.split
        |> fst

    method private current_data = Option.map (fun x -> List.assoc x input) curr
    method private table = Option.map (fun (_, y) -> y) self#current_data
    method private level = Option.map (fun (x, _) -> x) self#current_data

    method get ~r ~c = 
        match self#table with
        | None -> None
        | Some t -> Matrix.get_opt t ~r ~c

    method exists ~r ~c = (self#get ~r ~c) <> None

    method max_layer ~r ~c =
        match self#current_data with
        | None -> None
        | Some (level, table) ->
            Option.map (fun preds ->
                fst @@ List.fold_left2 (fun ((_, x) as z) y chr ->
                    if y > x then (chr, y) else z
                ) ('0', 0.0) preds (CLevel.to_header level)
            ) (Matrix.get_opt table ~r ~c)

    method iter f =
        match self#table with
        | None -> ()
        | Some matrix -> Matrix.iteri f matrix

    method iter_layer chr f =
        match self#level with
        | None -> ()
        | Some level -> let header = CLevel.to_header level in
            self#iter (fun ~r ~c t ->
                let elt, dat = 
                    List.fold_left2 (fun ((_, x) as o) chr y ->
                        if y > x then (chr, y) else o
                    ) ('0', 0.0) header t in
                if elt = chr then f ~r ~c dat)

    method statistics =
        match self#level with
        | None -> []
        | Some level -> let header = CLevel.to_header level in
            let counters = List.map (fun c -> c, ref 0) header in
            self#iter (fun ~r ~c t ->
                let chr, _ = 
                    List.fold_left2 (fun ((_, x) as o) chr y ->
                        if y > x then (chr, y) else o
                    ) ('0', 0.0) header t
                in incr (List.assoc chr counters)
            );
            List.map (fun (c, r) -> c, !r) counters

    method to_string () = 
        match self#current_data with
        | None -> "" (* TODO: Find a better solution to this! *)
        | Some (level, table) -> Aux.to_string level table

end


let filter entries =
    List.filter (fun {Zip.filename; _} ->
        Filename.dirname filename = "predictions"
    ) entries


let create ?zip source =
    match zip with
    | None -> new predictions []
    | Some ich -> let entries = Zip.entries ich in
        let assoc =
            List.map (fun ({Zip.filename; comment; _} as entry) ->
                let level = CLevel.of_string comment
                and matrix = Aux.of_string (Zip.read_entry ich entry)
                and id = Filename.(basename (chop_extension filename)) in
                id, (level, matrix)
            ) (filter entries)
        in new predictions assoc
