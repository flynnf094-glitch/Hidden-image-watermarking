%definition of lsb_embed function
function lsb_embed(inputImagePath, watermarkPath, outputImagePath, metadataPath, numBitsUsed)

%LSB-based spatial-domain watermark embedding
%input:
%inputImagePath: original image path
%watermarkPath: binary watermark image path
%outputImagePath: output watermarked image path
%metadataPath: metadata output path
%numBitsUsed: bit plane to use for embedding (1-8) representing embed strength

%check whether numBitsUsed is provided
if nargin < 5
    numBitsUsed = 1;
end

% validate numBitsUsed is in range 1-8
if numBitsUsed < 1 || numBitsUsed > 8
    error('numBitsUsed must be between 1 and 8.');
end

%Read the original image
img = imread(inputImagePath);

%check whether the image has 3 color channels
if size(img, 3) ~= 3
    error('Input image must be an RGB image.');
end

%get the image and watermark dimensions
[imgH, imgW, ~] = size(img);

%Read the watermark image
watermark = imread(watermarkPath);

%If the watermark is RGB, convert to grayscale
if size(watermark, 3) == 3
    watermarkDouble = double(watermark);
    watermarkGray = 0.299 * watermarkDouble(:, :, 1) + ...
                    0.587 * watermarkDouble(:, :, 2) + ...
                    0.114 * watermarkDouble(:, :, 3);
else
    watermarkGray = double(watermark);
end

%convert grayscale watermark to binary
watermarkBinary = watermarkGray > 128;

%get watermark dimensions
[wmH, wmW] = size(watermarkBinary);

%convert the 2D binary watermark into a 1D bit stream
watermarkBits = watermarkBinary(:);

%total number of watermark bits to embed
numWatermarkBits = length(watermarkBits);

%Metadata bits to embed
u16ImgH = dec2bin(uint16(wmH), 16);
u16ImgW = dec2bin(uint16(wmW), 16);
u32Length = dec2bin(uint32(numWatermarkBits), 32);
imgWArray = logical(u16ImgW(:)' - '0');
imgHArray = logical(u16ImgH(:)' - '0');
imgLengthArray = logical(u32Length(:)' - '0');

% Pack metadata bits to start of watermark bits array
watermarkBits = [imgWArray'; imgHArray'; imgLengthArray'; watermarkBits];

% MODIFICATION: We embed the watermark in small blocks and scramble the order 
% to resist blur, jpeg compression, and crop attacks.

% We repeat the bits across blocks of size block_size x block_size
% A larger block size gives better resistance to blur and jpeg compression.
block_size = 8;
num_blocks_h = floor(imgH / block_size);
num_blocks_w = floor(imgW / block_size);
num_blocks = num_blocks_h * num_blocks_w;

totalBitsToEmbed = length(watermarkBits);

%check whether the watermark fits in the image
if totalBitsToEmbed > num_blocks
    error('Watermark is too large for this image. Need %d blocks but only %d available.', ...
        totalBitsToEmbed, num_blocks);
end

% Assign blocks to watermark bits randomly (scrambled) to survive cropping
rng(12345); % Fixed seed for reproducible retrieval

% Calculate how many times each bit can be repeated
reps = floor(num_blocks / totalBitsToEmbed);
block_to_bit = repmat(1:totalBitsToEmbed, reps, 1);
block_to_bit = block_to_bit(:);

% Map remaining blocks randomly
rem_blocks = num_blocks - length(block_to_bit);
block_to_bit = [block_to_bit; randi(totalBitsToEmbed, rem_blocks, 1)];

% Scramble the block assignments
block_to_bit = block_to_bit(randperm(num_blocks));

% Map each pixel to its corresponding block
[cols, rows] = meshgrid(1:imgW, 1:imgH);
block_r = floor((rows - 1) / block_size) + 1;
block_c = floor((cols - 1) / block_size) + 1;

% Linear index of the block
block_idx = (block_c - 1) * num_blocks_h + block_r;

% Handle pixels that fall outside the full blocks (if image is not divisible by block_size)
% We'll map them to the last block safely
block_idx(block_idx > num_blocks) = num_blocks;

% Get the target bit index for every pixel in the image
pixel_target_bit_idx = block_to_bit(block_idx);

% Create a matrix of the bits to embed for every pixel
bits_to_embed = watermarkBits(pixel_target_bit_idx);

%extract the blue channel for embedding
blueChannel = img(:, :, 3);

% MODIFICATION: Change numBitsUsed to act as embed strength (bit plane).
% We embed exactly 1 bit at the specified bit plane for every pixel.
watermarkedBlueChannel = bitset(blueChannel, numBitsUsed, bits_to_embed);

%replace the blue channel with the modified one
watermarkedImg = img;
watermarkedImg(:, :, 3) = watermarkedBlueChannel;

%save the watermarked image
imwrite(watermarkedImg, outputImagePath);

%save metadata for retrieval
metadata.method = 'LSB spatial-domain watermarking';
metadata.inputImage = inputImagePath;
metadata.watermarkImage = watermarkPath;
metadata.outputImage = outputImagePath;
metadata.imageHeight = imgH;
metadata.imageWidth = imgW;
metadata.watermarkHeight = wmH;
metadata.watermarkWidth = wmW;
metadata.numWatermarkBits = numWatermarkBits;
metadata.numBitsUsed = numBitsUsed;
metadata.embeddingChannel = 'Blue (channel 3)';
metadata.embeddingOrder = 'Scrambled block repetition';
metadata.blockSize = block_size;

%convert metadata to JSON
jsonText = jsonencode(metadata);

%open the metadata file for writing
fid = fopen(metadataPath, 'w');

%write JSON text to the metadata file
fprintf(fid, '%s', jsonText);

%close the metadata file
fclose(fid);

fprintf('LSB watermark embedding complete.\n');
fprintf('Output image saved to: %s\n', outputImagePath);
fprintf('Metadata saved to: %s\n', metadataPath);
fprintf('Embedding used bit plane %d for embed strength.\n', numBitsUsed);
fprintf('Watermark size: %d x %d (%d bits total).\n', wmW, wmH, numWatermarkBits);

end
