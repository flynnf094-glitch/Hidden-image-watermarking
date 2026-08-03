function lsb_retrieve(inputImagePath, outputWatermarkPath, ...
                      numBitsUsed, jsonInputFilePath)

metadataLength = 64;

% MODIFICATION: We now treat numBitsUsed as the specific bit plane (1-8)
if numBitsUsed < 1 || numBitsUsed > 8
    error('numBitsUsed must be between 1 and 8.');
end

% Read attacked/watermarked image
img = imread(inputImagePath);

if size(img, 3) ~= 3
    error('Input image must be an RGB image.');
end

[imgH, imgW, ~] = size(img);

% Read JSON metadata to get block size and original dimensions
if ~isfile(jsonInputFilePath)
    error('JSON metadata file does not exist: %s', jsonInputFilePath);
end

jsonText = fileread(jsonInputFilePath);
metadata = jsondecode(jsonText);

if ~isfield(metadata, 'blockSize')
    block_size = 8; % Default if not present
else
    block_size = double(metadata.blockSize);
end

% Extract blue channel
blueChannel = img(:, :, 3);

% Identify pixels that are completely black (often caused by crop attacks)
% We don't want to use them for voting.
pixel_mask = img(:,:,1) > 0 | img(:,:,2) > 0 | img(:,:,3) > 0;

% We extract bits from every pixel at the specified bit plane
% Map 0 to -0.5 and 1 to 0.5 for majority voting
extracted_bits = double(bitget(blueChannel, numBitsUsed)) - 0.5;

% Ignore completely black pixels in voting
extracted_bits(~pixel_mask) = 0;

num_blocks_h = floor(imgH / block_size);
num_blocks_w = floor(imgW / block_size);
num_blocks = num_blocks_h * num_blocks_w;

% Check if we need to fall back to JSON metadata for watermark dimensions
headerValid = false;

% Attempt to decode embedded header
wmH = 0;
wmW = 0;
numWatermarkBits = 0;
totalBitsToEmbed = 0;

% Use JSON metadata primarily since header might be damaged
wmH = double(metadata.watermarkHeight);
wmW = double(metadata.watermarkWidth);
numWatermarkBits = double(metadata.numWatermarkBits);
totalBitsToEmbed = metadataLength + numWatermarkBits;

if isfield(metadata, 'numBitsUsed') && ...
        double(metadata.numBitsUsed) ~= numBitsUsed
    warning(['numBitsUsed input does not match the JSON value. ' ...
             'Using the JSON value.']);
    numBitsUsed = double(metadata.numBitsUsed);
    extracted_bits = double(bitget(blueChannel, numBitsUsed)) - 0.5;
    extracted_bits(~pixel_mask) = 0;
end

% Reproduce the random block assignment
rng(12345);
reps = floor(num_blocks / totalBitsToEmbed);
block_to_bit = repmat(1:totalBitsToEmbed, reps, 1);
block_to_bit = block_to_bit(:);

rem_blocks = num_blocks - length(block_to_bit);
block_to_bit = [block_to_bit; randi(totalBitsToEmbed, rem_blocks, 1)];

block_to_bit = block_to_bit(randperm(num_blocks));

% Map each pixel to its corresponding block
[cols, rows] = meshgrid(1:imgW, 1:imgH);
block_r = floor((rows - 1) / block_size) + 1;
block_c = floor((cols - 1) / block_size) + 1;

block_idx = (block_c - 1) * num_blocks_h + block_r;
block_idx(block_idx > num_blocks) = num_blocks;

% Target bit for every pixel
pixel_target_bit_idx = block_to_bit(block_idx);

% Accumulate votes
votes = accumarray(pixel_target_bit_idx(:), extracted_bits(:), [totalBitsToEmbed, 1]);

% Determine final bits based on majority vote (positive means 1, negative means 0)
allBits = (votes > 0);

%% Retrieve watermark data
watermarkStart = metadataLength + 1;
watermarkEnd = metadataLength + numWatermarkBits;

watermarkBits = allBits(watermarkStart:watermarkEnd);

%% Reconstruct and save watermark
reconstructedWatermark = reshape( ...
    logical(watermarkBits), [wmH, wmW]);

imwrite(uint8(reconstructedWatermark) * 255, ...
    outputWatermarkPath);

fprintf('LSB watermark retrieval complete.\n');
fprintf('Recovered watermark: %d x %d (%d bits).\n', ...
    wmW, wmH, numWatermarkBits);

if headerValid
    fprintf('Metadata source: embedded header.\n');
else
    fprintf('Metadata source: JSON file.\n');
end

end
