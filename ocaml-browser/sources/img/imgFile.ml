(* CastANet Browser - imgFile.ml *)

class file path = object 
    method path = path
    method base = Filename.basename path
    method archive = Filename.remove_extension path ^ ".zip"
end


let create path = new file path