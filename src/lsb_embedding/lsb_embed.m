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

% MODIFICATION: We now treat numBitsUsed as the specific bit plane (1-8)
% to embed in, which acts as the embed strength.
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

% MODIFICATION: We embed exactly 1 bit per pixel now.
maxCapacity = imgH * imgW;

%check whether the watermark fits in the image
if (numWatermarkBits + 64) > maxCapacity
    error('Watermark is too large for this image. Need %d pixels but only %d available.', ...
        (numWatermarkBits + 64), imgH * imgW);
end

%extract the blue channel for embedding
blueChannel = img(:, :, 3);

%convert to double for bit manipulation
blueDouble = double(blueChannel);

% Store total bits to embed (payload + 64-bit header that was prepended above)
totalBitsToEmbed = length(watermarkBits);

% MODIFICATION: Change embed order to a pseudo-random permutation to 
% distribute the watermark across the image.
rng(12345); % Fixed seed for reproducible retrieval
embedOrder = randperm(imgH * imgW);

for i = 1:totalBitsToEmbed
    pixelIndex = embedOrder(i);
    pixelVal = blueDouble(pixelIndex);

    % MODIFICATION: Change numBitsUsed to act as embed strength (bit plane).
    % We embed exactly 1 bit at the specified bit plane.
    
    % Clear the target bit plane
    pixelVal = bitset(uint8(pixelVal), numBitsUsed, 0);
    
    % Embed the watermark bit
    if watermarkBits(i)
        pixelVal = bitset(pixelVal, numBitsUsed, 1);
    end

    %store back
    blueDouble(pixelIndex) = double(pixelVal);
end

%replace the blue channel with the modified one
watermarkedImg = img;
watermarkedImg(:, :, 3) = uint8(blueDouble);

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
metadata.embeddingOrder = 'Pseudo-random order';

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
