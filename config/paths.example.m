% Machine-specific paths for hadamard-stim. Copy to config/paths.local.m
% (ignored by Git) and edit. Only the golden-fixture generator reads these;
% the +hadamard_stim package itself needs no configuration paths.
%
% yitong_data_root   Yitong Qi's "data&notes" folder. READ-ONLY: the generator
%                    only loads a few settings.mat files from it. Nothing may
%                    be written, moved or deleted under this folder.
% lab_code_root      The lab "Computer Code" share. The generator puts
%                    "Image Processing" on the path for the vm movie class,
%                    which Yitong's reconstruction code uses. The files it
%                    actually loads are hashed into each fixture's provenance.

hadamard_stim_paths.yitong_data_root = "/mnt/cohen-lab/Lab/Labmembers/Yitong Qi/data&notes";
hadamard_stim_paths.lab_code_root    = "/mnt/cohen-lab/Lab/Computer Code";
