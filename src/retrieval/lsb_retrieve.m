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

% Extract blue channel
blueChannel = img(:, :, 3);

% Extract every embedded bit in the same pseudo-random order used during embedding
% MODIFICATION: 1 bit per pixel now
maxExtractableBits = imgH * imgW;
allBits = zeros(maxExtractableBits, 1, 'uint8');

% MODIFICATION: Use the same fixed seed for the pseudo-random permutation
rng(12345);
embedOrder = randperm(imgH * imgW);

for i = 1:maxExtractableBits
    pixelIndex = embedOrder(i);
    pixelValue = blueChannel(pixelIndex);

    % MODIFICATION: Extract from the specific bit plane
    allBits(i) = bitget(pixelValue, numBitsUsed);
end

if length(allBits) < metadataLength
    error('Image does not contain enough pixels for the 64-bit header.');
end

%% Decode embedded header
wmW = bin2dec(char(allBits(1:16).' + '0'));
wmH = bin2dec(char(allBits(17:32).' + '0'));
numWatermarkBits = bin2dec(char(allBits(33:64).' + '0'));

%% Check whether embedded header is valid
headerValid = true;

if wmH < 1 || wmW < 1
    headerValid = false;
end

if numWatermarkBits ~= wmH * wmW
    headerValid = false;
end

if metadataLength + numWatermarkBits > length(allBits)
    headerValid = false;
end

%% Fall back to JSON metadata
if ~headerValid

    warning('Embedded LSB header is corrupted. Using JSON metadata.');

    if ~isfile(jsonInputFilePath)
        error('JSON metadata file does not exist: %s', ...
            jsonInputFilePath);
    end

    jsonText = fileread(jsonInputFilePath);
    metadata = jsondecode(jsonText);

    requiredFields = {
        'watermarkHeight'
        'watermarkWidth'
        'numWatermarkBits'
    };

    for fieldIndex = 1:length(requiredFields)
        if ~isfield(metadata, requiredFields{fieldIndex})
            error('JSON metadata is missing field "%s".', ...
                requiredFields{fieldIndex});
        end
    end

    wmH = double(metadata.watermarkHeight);
    wmW = double(metadata.watermarkWidth);
    numWatermarkBits = double(metadata.numWatermarkBits);

    if isfield(metadata, 'numBitsUsed') && ...
            double(metadata.numBitsUsed) ~= numBitsUsed

        warning(['numBitsUsed input does not match the JSON value. ' ...
                 'Using the JSON value.']);

        numBitsUsed = double(metadata.numBitsUsed);

        % Re-extract bits using the JSON numBitsUsed value
        maxExtractableBits = imgH * imgW;
        allBits = zeros(maxExtractableBits, 1, 'uint8');

        rng(12345);
        embedOrder = randperm(imgH * imgW);

        for i = 1:maxExtractableBits
            pixelIndex = embedOrder(i);
            pixelValue = blueChannel(pixelIndex);
            
            allBits(i) = bitget(pixelValue, numBitsUsed);
        end
    end

    % Validate JSON values
    if wmH < 1 || wmW < 1 || ...
            numWatermarkBits ~= wmH * wmW
        error('JSON watermark metadata is invalid.');
    end

    if metadataLength + numWatermarkBits > length(allBits)
        error(['Watermark requires %d bits, but only %d payload bits ' ...
               'can be extracted from the image.'], ...
               numWatermarkBits, ...
               length(allBits) - metadataLength);
    end
end

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
