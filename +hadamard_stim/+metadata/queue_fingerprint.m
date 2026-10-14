function q = queue_fingerprint(sequences, repeats)
%QUEUE_FINGERPRINT A DMD queue's identity, in the bytes Yitong's loader sent.
%
%   q = hadamard_stim.metadata.queue_fingerprint(sequences, repeats)
%
%   sequences{k} canvas [W x L x n_k] logical, repeats(k) its repeat count.
%   Each sequence is packed with his alp_logical_to_btd and hashed in the
%   layout his load_sequence_multi handed to AlpSeqPut, so a queue loaded
%   on the rig and one in the trace golden have the same hashes.
%
%   q.n_sequences, q.picnum, q.repeat, q.sha256 (per sequence),
%   q.combined_sha256 (all sequences' bytes in order)
n = numel(sequences);
q.n_sequences = n;
q.picnum = cellfun(@(m) size(m, 3), sequences(:)');
q.repeat = repeats(:)';
q.sha256 = strings(1, n);
bytes = cell(1, n);
for k = 1:n
    data = permute(hadamard_stim.yitong.alp_logical_to_btd(sequences{k}), [3 1 2]);
    q.sha256(k) = hadamard_stim.metadata.sha256(data);
    bytes{k} = reshape(data, [], 1);
end
q.combined_sha256 = hadamard_stim.metadata.sha256(vertcat(uint8([]), bytes{:}));
end
