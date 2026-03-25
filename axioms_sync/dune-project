(lang dune 3.17)

(dialect
 (name mlx)
 (implementation
  (extension mlx)
  (merlin_reader mlx)
  (preprocess
   (run mlx-pp %{input-file}))))

(pin
 (url "git+ssh://git@github.com/finalclass/well.git")
 (package (name well)))

(package
 (name axioms_sync)
 (version 0.0.1)
 (allow_empty)
 (synopsis "A well web application")
 (depends
  (ocaml (>= 5.4))
  mlx
  well
  eio
  eio_main
  yojson
  sqlite3
  ppx_deriving_yojson
  tls-eio
  ca-certs
  mirage-crypto-rng))
