function im = synthetic_movie_mean(ref, orange_v, n_stim_before)
%SYNTHETIC_MOVIE_MEAN Mean frame of a stimulation movie: cell signal scales
%with orange voltage and bleaches with the number of earlier stimulation
%trials. Feeds Yitong's bleaching estimate in the trace golden.
tau = 400;
cells = max(ref - median(ref(:)), 0);
im = 100 + orange_v * cells * exp(-n_stim_before / tau);
end
