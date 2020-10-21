(* CastANet - uI_Layers.ml *)

open Printf


type radio_ext = {
  r_radio : GButton.radio_tool_button;
  r_label : GMisc.label;
  r_image : GMisc.image;
}


module type RADIO = sig
  val toolbar : GButton.toolbar
  val radios : (char * radio_ext) list
end 


module type PARAMS = sig
  val packing : GObj.widget -> unit
  val remove : GObj.widget -> unit
  val current : unit -> AmfLevel.t
  val radios : (AmfLevel.t * GButton.radio_button) list
end


module type S = sig
  val current : unit -> char
  val set_label : char -> int -> unit
  val set_callback : 
    (char -> 
      GButton.radio_tool_button -> GMisc.label -> GMisc.image -> unit) -> unit
end



module Toolbox = struct

    let add_item packing a_ref g_ref i chr =
        let active = !a_ref and group = !g_ref in
        let r_radio = GButton.radio_tool_button ~active ?group ~packing () in
        if active then (a_ref := false; g_ref := Some r_radio);
        let hbox = GPack.hbox ~spacing:2 ~packing:r_radio#set_icon_widget () in
        let r_image = GMisc.image ~width:24 ~packing:hbox#add ()
        and r_label = GMisc.label
            ~markup:"<small><tt>000000</tt></small>" 
            ~packing:hbox#add () in
        let style = if chr = '*' then `RGBA else `GREY in
        r_image#set_pixbuf (AmfIcon.get chr style `SMALL);
        chr, {r_radio; r_label; r_image}

    let make level =
        let code_list = '*' :: AmfLevel.to_header level in
        let module T = struct
            let toolbar = GButton.toolbar
                ~orientation:`VERTICAL
                ~style:`ICONS
                ~width:98 ~height:340 ()
            let active = ref true
            let group = ref None
            let packing = toolbar#insert
            let radios = 
                UIHelper.separator packing;
                UIHelper.label packing "<b><small>Layer</small></b>";
                List.mapi (add_item packing active group) code_list
        end in (module T : RADIO)

end



module Make (P : PARAMS) : S = struct
    
    let toolboxes = 
        let make level = level, Toolbox.make level in
        List.map make AmfLevel.all_flags

  let current_widget = ref None

  let detach () = Option.iter (fun widget -> P.remove widget) !current_widget

    let attach level =
        detach ();
        let radio = List.assoc level toolboxes in
        let module T = (val radio : RADIO) in
        let widget = T.toolbar#coerce in
        P.packing widget;
        current_widget := Some widget
 
    (* Returns radio buttons active at the current level. *)
    let current_level_radios () =
        let level = P.current () in
        let open (val (List.assoc level toolboxes) : RADIO) in
        radios

    (* Extracts a radio button from an association list. *)
    let get_radio_ext x = current_level_radios ()
        |> List.find (fun (y, _) -> x = y)
        |> snd

    (* Returns the "joker" radio button. *)
    let get_joker () = get_radio_ext '*'

    let current () = current_level_radios ()
        |> List.find (fun x -> (snd x).r_radio#get_active)
        |> fst
  
    let is_active chr = (get_radio_ext chr).r_radio#get_active

    let set_image chr = (get_radio_ext chr).r_image#set_pixbuf

    let set_label chr num =
    ksprintf (get_radio_ext chr).r_label#set_label 
        "<small><tt>%06d</tt></small>" num
  
    let set_callback f =
        List.iter (fun (level, radio) ->
            let module T = (val radio : RADIO) in
            List.iter (fun (chr, {r_radio; r_label; r_image}) ->
                let callback () = f chr r_radio r_label r_image in
                ignore (r_radio#connect#after#toggled ~callback)
            ) T.radios
    ) toolboxes  
 
    let iter f =
        List.iter (fun (chr, r) -> 
            f chr r.r_radio r.r_label r.r_image
        ) (current_level_radios ()) 

    let _ =
        attach `COLONIZATION;
        List.iter (fun (level, radio) ->
            let callback () = if radio#active then attach level in
            ignore (radio#connect#toggled ~callback)
        ) P.radios;
        let callback chr radio _ icon =
            let style = if radio#get_active then `RGBA else `GREY in
            icon#set_pixbuf (AmfIcon.get chr style `SMALL)
        in set_callback callback
end
