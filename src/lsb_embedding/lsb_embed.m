%definition of lsb_embed function
function lsb_embed(inputImagePath, watermarkPath, outputImagePath, metadataPath, numBitsUsed)

%LSB-based spatial-domain watermark embedding
%input:
%inputImagePath: original image path
%watermarkPath: binary watermark image path
%outputImagePath: output watermarked image path
%metadataPath: metadata output path
%numBitsUsed: number of least significant bits to use for embedding (1-4)
%main idea:
%1.Read original image
%2.Read and binarize watermark image
%3.Embed watermark bits into the least significant bits of the blue channel
%4.Traverse pixels in raster order, replacing the LSB(s) with watermark bits
%5.Save the watermarked image
%6.Save metadata for retrieval

%check whether numBitsUsed is provided (input provided < 5)
%if not provided, default set to 1
if nargin < 5
    numBitsUsed = 1;
end

%validate numBitsUsed is in range 1-4
if numBitsUsed < 1 || numBitsUsed > 4
    error('numBitsUsed must be between 1 and 4.');
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
%if pixel > 128, make it 1
%if pixel <= 128, make it 0
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

%Pack metadata bits to start of watermark bits array
% Pack metadata bits to start of watermark bits array
watermarkBits = [imgWArray'; imgHArray'; imgLengthArray'; watermarkBits];

%calculate the maximum number of bits we can embed
%using the blue channel with the specified number of LSBs

% BUG FIX: the original line incorrectly added 64 to the true image capacity,
% which could allow overly large watermarks to pass the check.
% The actual capacity is strictly the number of pixels times bits-per-pixel.
%
% ORIGINAL (buggy):
%   maxCapacity = (imgH * imgW * numBitsUsed) + 64;
%
% After prepending the 64-bit header, the total bits to embed is
% (numWatermarkBits + 64), so the check must compare that total against
% the true capacity.
maxCapacity = imgH * imgW * numBitsUsed; % FIX: removed erroneous + 64

%check whether the watermark fits in the image
% ORIGINAL (buggy):
%   if numWatermarkBits > maxCapacity
% FIX: compare total bits (payload + 64-bit header) against true capacity
if (numWatermarkBits + 64) > maxCapacity
    error('Watermark is too large for this image with %d LSB bit(s). Need %d pixels but only %d available.', ...
        numBitsUsed, ceil((numWatermarkBits + 64) / numBitsUsed), imgH * imgW);
end

%extract the blue channel for embedding
%blue channel is chosen because human eyes are least sensitive to changes
%in the blue channel compared to red and green
blueChannel = img(:, :, 3);

%convert to double for bit manipulation
blueDouble = double(blueChannel);

%embed the watermark bits into the LSBs of the blue channel
%we traverse pixels in raster order (row by row, left to right)
%
% NOTE ON LSB FRAGILITY:
% LSB watermarking stores data in the 1-2 least significant bits of each pixel.
% These bits are the first to be destroyed by any signal processing:
%
%   Gaussian noise (sigma=10): adds random offsets averaging ~10 to pixel values.
%   A 1-bit change is only 1 unit, so noise with sigma=10 almost always flips
%   the embedded LSBs, corrupting the entire watermark payload and header.
%
%   JPEG compression (quality 50): uses lossy DCT quantization that rounds
%   pixel values to the nearest quantization step. LSBs are the bits that
%   quantization rounding changes first, so virtually every embedded bit is
%   flipped after JPEG re-encoding.
%
%   Crop + resize: after cropping 80% of the image and nearest-neighbor
%   resizing back to the original dimensions, the pixel at position (r,c)
%   in the output comes from a different (r',c') in the watermarked image.
%   When lsb_retrieve reads pixels in the original raster order it therefore
%   reads bits from the wrong physical locations, corrupting both the 64-bit
%   header (so the size/length fields become garbage) and every payload bit.

% Store total bits to embed (payload + 64-bit header that was prepended above)
totalBitsToEmbed = length(watermarkBits); % = numWatermarkBits + 64

bitIndex = 1;

for pixelIndex = 1:(imgH * imgW)
    % BUG FIX: the original condition was (bitIndex > numWatermarkBits).
    % After prepending the 64-bit header, watermarkBits has
    % (numWatermarkBits + 64) entries.  Breaking at numWatermarkBits left
    % the last 64 payload bits unembedded, corrupting retrieval even on an
    % unattacked image.
    %
    % ORIGINAL (buggy):
    %   if bitIndex > numWatermarkBits
    if bitIndex > totalBitsToEmbed % FIX: use total length including header
        break;
    end

    %get current pixel value
    pixelVal = blueDouble(pixelIndex);

    %clear the least significant bit(s)
    %create a mask that zeros out the lowest numBitsUsed bits
    clearMask = 256 - 2^numBitsUsed;
    pixelVal = bitand(uint8(pixelVal), uint8(clearMask));
    pixelVal = double(pixelVal);

    %embed bits into the LSBs
    %collect up to numBitsUsed bits from the watermark stream
    bitsToEmbed = 0;
    for b = 1:numBitsUsed
        if bitIndex <= length(watermarkBits)
            %place each watermark bit into the correct position
            %MSB of embedded bits goes into the highest LSB position
            bitsToEmbed = bitsToEmbed + watermarkBits(bitIndex) * 2^(numBitsUsed - b);
            bitIndex = bitIndex + 1;
        end
    end

    %combine the cleared pixel with the embedded bits
    pixelVal = pixelVal + bitsToEmbed;

    %store back
    blueDouble(pixelIndex) = pixelVal;
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
metadata.embeddingOrder = 'Raster order (row-major)';

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
fprintf('Embedding used %d LSB bit(s) per pixel.\n', numBitsUsed);
fprintf('Watermark size: %d x %d (%d bits total).\n', wmW, wmH, numWatermarkBits);

end
