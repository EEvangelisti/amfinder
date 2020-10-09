(* CastANet - cImage.ml *)

open Printf

module Aux = struct
    let blank =
        let pix = GdkPixbuf.create ~width:180 ~height:180 () in
        GdkPixbuf.fill pix 0l;
        pix
end



class image path edge = 

    (* File settings. *)
    let file = ImgFile.create path in

    (* Source object. *)   
    let pixbuf = GdkPixbuf.from_file path in
    let source = ImgSource.create pixbuf edge in
    
    (* Drawing parameters. *)   
    let brush = ImgBrush.create source in
    let cursor = ImgCursor.create source brush
    and pointer = ImgPointer.create source brush in
    
    (* Image segmentation. *)   
    let small_tiles = ImgTileMatrix.create pixbuf source brush#edge
    and large_tiles = ImgTileMatrix.create pixbuf source 180 in

    (* Annotations, predictions and activations. *)
    let annotations, predictions, activations = 
        let zip = match Sys.file_exists file#archive with
            | true  -> Some (Zip.open_in file#archive)
            | false -> None in
        let annotations = ImgAnnotations.create ?zip source
        and predictions = ImgPredictions.create ?zip source
        and activations = ImgActivations.create ?zip source in
        Option.iter Zip.close_in zip;
        (annotations, predictions, activations) in

object (self)

    val draw = ImgDraw.create 
        small_tiles
        brush
        annotations
        predictions

    val ui = ImgUI.create
        cursor
        annotations
        predictions

    val mutable exit_funcs = []

    initializer
        (* Cursor drawing functions. *)
        cursor#set_paint draw#cursor;
        cursor#set_paint (fun ?sync:_ ~r:_ ~c:_ -> self#magnified_view);
        cursor#set_erase self#draw_annotated_tile;
        (* Pointer drawing functions. *)
        pointer#set_paint draw#pointer;
        pointer#set_erase self#draw_annotated_tile;
        annotations#current_level
        |> predictions#ids
        |> AmfUI.Predictions.set_choices

    method at_exit f = exit_funcs <- f :: exit_funcs

    method file = file
    method brush = brush
    method cursor = cursor
    method source = source
    method pointer = pointer
    method small_tiles = small_tiles
    method large_tiles = large_tiles
    method annotations = annotations
    method predictions = predictions

    method show_predictions () =
        let preds = AmfUI.Predictions.get_active () in
        predictions#set_current preds;
        self#mosaic ()    

    (* TODO: it should be possible to choose the folder! *)
    method screenshot () =
        let screenshot = AmfUI.Magnifier.screenshot () in
        let r, c = cursor#get in
        let filename = sprintf "AMF_screenshot_R%d_C%d.jpg" r c in
        AmfLog.info "Saving screenshot as %S" filename;
        GdkPixbuf.save ~filename ~typ:"jpeg" screenshot

    (* + self#magnified_view () and toggle buttons *)
    method private draw_annotated_tile ?(sync = false) ~r ~c () =
        let sync = false in
        draw#tile ~sync ~r ~c ();
        if cursor#at ~r ~c then brush#cursor ~sync ~r ~c ()
        else if pointer#at ~r ~c then brush#pointer ~sync ~r ~c ()
        else draw#overlay ~sync ~r ~c ();
        if sync then brush#sync ()

    method private may_overlay_cam ~i ~j ~r ~c =
        if i = 1 && j = 1 && predictions#active && activations#active then (
             match predictions#current with
             | None -> large_tiles#get (* No active prediction set. *)
             | Some id -> match annotations#current_layer with
                | '*' -> (* let's find the top layer. *)
                    begin match predictions#max_layer ~r ~c with
                        | None -> large_tiles#get
                        | Some max -> activations#get id max
                    end
                | chr -> activations#get id chr
        ) else large_tiles#get

    method magnified_view () =
        let r, c = cursor#get in
        for i = 0 to 2 do
            for j = 0 to 2 do
                let ri = r + i - 1 and cj = c + j - 1 in
                let get = self#may_overlay_cam ~i ~j ~r:ri ~c:cj in            
                let pixbuf = match get ~r:ri ~c:cj with
                    | None -> Aux.blank
                    | Some x -> x
                in AmfUI.Magnifier.set_pixbuf ~r:i ~c:j pixbuf
            done
        done

    method private update_counters () =
        let source =
            match predictions#active with
            | true  -> predictions#statistics
            | false -> annotations#statistics (annotations#current_level)
        in List.iter (fun (c, n) -> AmfUI.Layers.set_label c n) source

    method mosaic ?(sync = false) () =
        brush#background ~sync:false ();
        small_tiles#iter (fun ~r ~c pixbuf ->
            brush#pixbuf ~sync:false ~r ~c pixbuf;
            self#draw_annotated_tile ~sync:false ~r ~c ()
        );
        if sync then brush#sync ()

    method show () =
        self#mosaic ();
        let r, c = cursor#get in
        brush#cursor ~sync:true ~r ~c ();
        self#magnified_view ();
        self#update_counters ()

    method save () =
        let zip = file#archive in
        List.iter (fun f -> f (ignore zip)) exit_funcs
        (* CTable.save ~zip annotations predictions *)

end



let create ~edge path =
    if Sys.file_exists path then new image path edge
    else invalid_arg "AmfImage.load: File not found"
