(* AMFinder - img/imgActivations.ml
 *
 * MIT License
 * Copyright (c) 2021 Edouard Evangelisti
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *)

open Printf
open Morelib
open ImgShared

class type cls = object
    method active : bool
    method get : string -> char -> r:int -> c:int -> GdkPixbuf.pixbuf option   
    method dump : Zip.out_file -> unit
end


class activations
    (source : ImgSource.cls) 
    (input : (string * (char * GdkPixbuf.pixbuf)) list) edge 

= object

    val hash =
        let hash = Hashtbl.create 11 in
        List.iter (fun (id, data) ->
            match Hashtbl.find_opt hash id with
            | None -> Hashtbl.add hash id [data]
            | Some old -> Hashtbl.replace hash id (data :: old)
        ) input;
        hash

    method active = AmfUI.Predictions.cams#get_active

    method get id chr ~r ~c =
        try
            let pixbuf = List.assoc chr (Hashtbl.find hash id) in
            let src_x = c * source#edge 
            and src_y = r * source#edge in
            crop_pixbuf ~src_x ~src_y ~edge:source#edge pixbuf
            |> resize_pixbuf edge
            |> Option.some
        with exn -> 
            AmfLog.warning "ImgTileMatrix.activations#get \
            %S %C ~r=%d ~c=%d triggered exception %S" id chr r c 
            (Printexc.to_string exn);
            None

    method dump och =
        List.iter (fun (id, (chr, pixbuf)) ->
            let buf = Buffer.create 100 in
            GdkPixbuf.save_to_buffer pixbuf ~typ:"jpeg" buf;
            Zip.add_entry
                ~comment:(String.make 1 chr)
                (Buffer.contents buf) och
                (sprintf "activations/%s.%c.jpg" id chr)
        ) input

end

let filter entries =
    List.filter (fun e -> 
        Filename.dirname e.Zip.filename = "activations"
    ) entries

let create ?zip source =
    match zip with
    | None -> new activations source [] 180
    | Some ich -> let entries = Zip.entries ich in
        let table = 
            List.map (fun ({Zip.filename; comment; _} as entry) ->
                let chr = Scanf.sscanf comment "%c" Char.uppercase_ascii
                and id = Filename.chop_extension filename 
                    |> Filename.chop_extension
                    |> Filename.basename in
                let tmp, och = Filename.open_temp_file
                    ~mode:[Open_binary] 
                    "amfinder" ".jpg" in
                Zip.copy_entry_to_channel ich entry och;
                close_out och;
                AmfLog.info "Loading activation map %S" tmp;
                let pixbuf = GdkPixbuf.from_file tmp in
                Sys.remove tmp;
                id, (chr, pixbuf) 
            ) (filter entries)
        in new activations source table 180
