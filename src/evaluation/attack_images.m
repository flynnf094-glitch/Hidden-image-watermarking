function attackList = attack_images(inputImagePath, outputFolder, methodKey)
%ATTACK_IMAGES Create attacked versions of a watermarked image.
%
% Works for both:
%   DCT watermarked image
%   LSB watermarked image
%
% Attacks:
%   no attack copy
%   JPEG compression
%   Gaussian noise
%   3x3 blur
%   center crop 80% then resize back

if nargin < 3
    methodKey = 'method';
end

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

img = imread(inputImagePath);
imgDouble = double(img);

attackList = struct('name', {}, 'path', {});

% ============================================================
% Attack 0: no attack copy
% ============================================================

attackName = 'no_attack';
outputPath = fullfile(outputFolder, [methodKey '_' attackName '.png']);

imwrite(img, outputPath);

attackList(end+1).name = attackName;
attackList(end).path = outputPath;

% ============================================================
% Attack 1: JPEG compression
% ============================================================
%
% WHY THIS DESTROYS LSB WATERMARKS:
% JPEG uses lossy DCT-based quantization.  Quantization rounds coefficients
% to the nearest step size, which alters pixel values by ±several units on
% average.  Even a single-unit change flips a 1-bit LSB.  At quality 50
% the rounding errors are large enough to corrupt virtually every embedded
% LSB, making the recovered watermark indistinguishable from noise.
% DCT-domain watermarks survive because they embed into mid-frequency
% coefficients that quantization preserves much better than the LSBs.

attackName = 'jpeg_q50';

jpegPath = fullfile(outputFolder, [methodKey '_' attackName '.jpg']);
outputPath = fullfile(outputFolder, [methodKey '_' attackName '.png']);

imwrite(img, jpegPath, 'Quality', 50);
jpegImg = imread(jpegPath);
imwrite(jpegImg, outputPath);

attackList(end+1).name = attackName;
attackList(end).path = outputPath;

% ============================================================
% Attack 2: Gaussian noise
% ============================================================
%
% WHY THIS DESTROYS LSB WATERMARKS:
% LSB embedding stores data in the least significant 1-4 bits of pixel
% values, representing changes of 1 to 15 out of 255.  Adding Gaussian
% noise with noiseSigma = 10 shifts pixel values by ~10 on average --
% roughly 10x the magnitude of a single LSB change.  Nearly every pixel
% is shifted by more than 1, so nearly every embedded bit is flipped.
% The 64-bit header (width / height / length fields) is equally destroyed,
% forcing retrieval to fall back to the JSON metadata file; but even with
% correct metadata the payload bits are all corrupted.

attackName = 'gaussian_noise';

rng(1);
noiseSigma = 10;

noisyImg = imgDouble + noiseSigma * randn(size(imgDouble));
noisyImg = uint8(min(max(noisyImg, 0), 255));

outputPath = fullfile(outputFolder, [methodKey '_' attackName '.png']);
imwrite(noisyImg, outputPath);

attackList(end+1).name = attackName;
attackList(end).path = outputPath;

% ============================================================
% Attack 3: 3x3 average blur
% ============================================================

attackName = 'blur_3x3';

kernel = ones(3, 3) / 9;

blurredImg = zeros(size(imgDouble));

for ch = 1:size(imgDouble, 3)
    blurredImg(:, :, ch) = conv2(imgDouble(:, :, ch), kernel, 'same');
end

blurredImg = uint8(min(max(blurredImg, 0), 255));

outputPath = fullfile(outputFolder, [methodKey '_' attackName '.png']);
imwrite(blurredImg, outputPath);

attackList(end+1).name = attackName;
attackList(end).path = outputPath;

% ============================================================
% Attack 4: center crop 80%, then resize back
% ============================================================
%
% WHY THIS DESTROYS LSB WATERMARKS:
% LSB embedding reads and writes pixels in a fixed raster order (column-
% major in MATLAB's linear indexing).  Cropping 80% of the center and
% nearest-neighbor resizing back to the original dimensions remaps every
% pixel: the value at index k in the resized image was originally at a
% different index k' in the watermarked image.  When lsb_retrieve reads
% pixels in the original raster order it therefore reads bits from the
% wrong physical locations.  The 64-bit header is destroyed first, which
% causes the headerValid check to fail; even with the JSON fallback, all
% payload bits are read from misaligned pixel positions and the recovered
% watermark is meaningless.
% DCT-domain methods are also harmed by cropping but can be made more
% resilient by embedding in global frequency components rather than fixed
% spatial positions.

attackName = 'crop80_resize';

cropRatio = 0.80;

[h, w, ~] = size(img);

cropH = round(h * cropRatio);
cropW = round(w * cropRatio);

rowStart = floor((h - cropH) / 2) + 1;
colStart = floor((w - cropW) / 2) + 1;

croppedImg = img(rowStart:rowStart+cropH-1, ...
                 colStart:colStart+cropW-1, :);

resizedBack = nearest_resize(croppedImg, h, w);

outputPath = fullfile(outputFolder, [methodKey '_' attackName '.png']);
imwrite(resizedBack, outputPath);

attackList(end+1).name = attackName;
attackList(end).path = outputPath;

fprintf('Attack images saved to:\n%s\n', outputFolder);

end


function out = nearest_resize(img, newH, newW)
% Resize image using nearest-neighbor method.
% This avoids imresize because imresize may need Image Processing Toolbox.

[oldH, oldW, channels] = size(img);

out = zeros(newH, newW, channels, 'uint8');

for r = 1:newH

    oldR = round((r - 0.5) * oldH / newH + 0.5);
    oldR = min(max(oldR, 1), oldH);

    for c = 1:newW

        oldC = round((c - 0.5) * oldW / newW + 0.5);
        oldC = min(max(oldC, 1), oldW);

        out(r, c, :) = img(oldR, oldC, :);
    end
end

end