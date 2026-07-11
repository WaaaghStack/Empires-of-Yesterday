This folder receives the built native libraries (G5 packaging).

After `cargo build` (debug) or `cargo build --release` inside rust/empire_territory/:

Windows example (copy the produced DLL here with the exact name expected by empire_territory.gdextension):

  From target\debug\empire_territory.dll   -> empire_territory.windows.template_debug.x86_64.dll
  From target\release\empire_territory.dll -> empire_territory.windows.template_release.x86_64.dll

Do NOT leave ~*.TMP lock files from OneDrive/antivirus in this folder.

The .gdextension file (sibling to this bin/ folder) tells Godot where to find them using res:// paths.

Live World Conquest requires these DLLs (A1/G3 fail-closed if missing).

You can automate the copy later with a small build.rs or post-build script.
