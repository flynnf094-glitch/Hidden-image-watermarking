clc;
clear;
close all;

% Get the folder where this script is located:
% e.g., D:\Hidden-image-watermarking\src\lsb_embedding
scriptFolder = fileparts(mfilename('fullpath'));

% Go two folders up to project root:
% e.g., D:\Hidden-image-watermarking
projectRoot = fullfile(scriptFolder, '..', '..');

% Create full absolute paths
inputImagePath = fullfile(projectRoot, 'data', 'input', 'original.png');
watermarkPath = fullfile(projectRoot, 'data', 'input', 'watermark.png');
outputImagePath = fullfile(projectRoot, 'data', 'output', 'lsb_watermarked.png');
metadataPath = fullfile(projectRoot, 'data', 'output', 'lsb_metadata.json');

% Make sure output folder exists
outputFolder = fullfile(projectRoot, 'data', 'output');
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% Debug check
disp(inputImagePath)
disp(exist(inputImagePath, 'file'))

% Number of LSBs to use for embedding (1 = most invisible, up to 4)
numBitsUsed = 6;

lsb_embed(inputImagePath, watermarkPath, outputImagePath, metadataPath, numBitsUsed);
