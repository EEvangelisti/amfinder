(* CastANet Browser - imgPointer.ml *)

class pointer 
(  img_source : ImgSource.source)
  (img_brush : ImgBrush.brush)

= object (self)

    val mutable pos = None
    val mutable erase = (fun ?sync:_ ~r:_ ~c:_ () -> ())
    val mutable paint = (fun ?sync:_ ~r:_ ~c:_ () -> ())

    method get = pos
    method set_erase f = erase <- f
    method set_paint f = paint <- f

    method at ~r ~c =
        match pos with
        | None -> false
        | Some (cr, cc) -> r = cr && c = cc

    method private update_pointer_pos ~r ~c =
        if r >= 0 && r < img_source#rows 
        && c >= 0 && c < img_source#columns then
            begin 
                match pos with
                | Some old when old = (r, c) -> () (* same position *)
                | _ -> 
                    Option.iter (fun (r, c) ->
                        pos <- None;
                        erase ~sync:false ~r ~c ()
                    ) pos;
                    pos <- Some (r, c);
                    paint ~sync:true ~r ~c ();
            end
        else Option.iter (fun (r, c) -> pos <- None; erase ~sync:true ~r ~c ()) pos

    method track ev =
        let x = truncate (GdkEvent.Motion.x ev) - img_brush#x_origin
        and y = truncate (GdkEvent.Motion.y ev) - img_brush#y_origin in
        self#update_pointer_pos ~r:(y / img_brush#edge) ~c:(x / img_brush#edge);
        false

    method leave (_ : GdkEvent.Crossing.t)  =
        Option.iter (fun (r, c) -> pos <- None; erase ~sync:true ~r ~c ()) pos;
        false

end



let create x y = new pointer x y