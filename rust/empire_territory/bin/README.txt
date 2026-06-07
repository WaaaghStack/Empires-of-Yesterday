This folder receives the built native libraries.

After `cargo build` (debug) or `cargo build --release` inside rust/empire_territory/:

Windows example (copy the produced DLL here with the exact name expected by empire_territory.gdextension):

  From target\debug\   -> empire_territory.windows.template_debug.x86_64.dll
  From target\release\ -> empire_territory.windows.template_release.x86_64.dll

The .gdextension file (sibling to this bin/ folder) tells Godot where to find them using res:// paths.

You can automate the copy later with a small build.rs or post-build script.
