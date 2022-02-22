(*----------------------------------------------------------------------
   Copyright (c) 2022 Patrick Ferris <patrick@sirref.org>
   Distributed under the MIT license. See terms at the end of this file.
  ----------------------------------------------------------------------*)

module Overlapped = struct
  type t

  external create : unit -> t = "ocaml_iocp_make_overlapped"
end

module Handle = struct
  type t = Unix.file_descr
  let to_unix t = t
  external openfile : string -> Unix.open_flag list -> Unix.file_perm -> t = "ocaml_iocp_unix_open"
end

(* Bindings to C API *)
module Iocp = struct
  type t = Handle.t
  (* A handle to an I/O completion port *)

  type id = Heap.ptr

  (* Completion Port Management *)
  external create_io_completion_port : int -> t = "ocaml_iocp_create_io_completion_port"
  external create_io_completion_port_with_fd : Handle.t -> 'a -> int -> t = "ocaml_iocp_create_io_completion_port_with_fd"

  type completion_status = private
    | Cs_none
    | Cs_some of { heap_ptr : id; bytes_transferred : int } 

  external get_queued_completion_status : t -> completion_status = "ocaml_iocp_get_queued_completion_status"
  (* external get_queue_completion_status_timeout : t -> int -> completion_status = "ocaml_iocp_get_queued_completion_status_timeout"  *)

  (* Operations *)
  external read_file : t -> Handle.t -> id -> Cstruct.buffer -> int -> Overlapped.t -> bool = "ocaml_iocp_read_file_bytes" "ocaml_iocp_read_file"
  external write_file : t -> Handle.t -> id -> Cstruct.buffer -> int -> Overlapped.t -> bool = "ocaml_iocp_write_file_bytes" "ocaml_iocp_write_file"
end

type 'a t = { 
  iocp : Iocp.t;
  data : 'a Heap.t;
  mutable dirty : bool;
}

let create ?(threads=0) () =
  { iocp = Iocp.create_io_completion_port threads; data = Heap.create 128; dirty = false }

let create_with_fd ?(threads=0) fd data = 
  { iocp = Iocp.create_io_completion_port_with_fd fd data threads; data = Heap.create 128; dirty = false }

type 'a completion_status = { data : 'a; bytes_transferred : int }

let get_queued_completion_status t = 
  match Iocp.get_queued_completion_status t.iocp with
    | Cs_none -> None
    | Cs_some { heap_ptr; bytes_transferred } ->
      let data = Heap.free t.data heap_ptr in
      Some { data; bytes_transferred }

type 'a job = 'a Heap.entry

let with_id_full : type a. a t -> (Heap.ptr -> bool) -> a -> extra_data:'b -> a job option =
  fun t fn datum ~extra_data ->
    match Heap.alloc t.data datum ~extra_data with
    | exception Heap.No_space -> None
    | entry ->
      let ptr = Heap.ptr entry in
      let has_space = fn ptr in
      if has_space then (
        t.dirty <- true;
        Some entry
      ) else (
        ignore (Heap.free t.data ptr : a);
        None
      )
  
let with_id t fn a = with_id_full t fn a ~extra_data:()

let read_file t fd buf num_bytes data ol =
  with_id t (fun id -> Iocp.read_file t.iocp fd id (Cstruct.to_bigarray buf) num_bytes ol) data

let write_file t fd buf num_bytes data ol =
  with_id t (fun id -> Iocp.write_file t.iocp fd id (Cstruct.to_bigarray buf) num_bytes ol) data

(*---------------------------------------------------------------------------
  Copyright (c) 2022 <patrick@sirref.org>
  
  Permission to use, copy, modify, and/or distribute this software for any
  purpose with or without fee is hereby granted, provided that the above
  copyright notice and this permission notice appear in all copies.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.
  ---------------------------------------------------------------------------*)