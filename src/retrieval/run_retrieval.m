%Get folder where this script is located
scriptFolder = fileparts(mfilename('fullpath'));

%Go two folders up to the project root
projectRoot = fullfile(scriptFolder, '..', '..');

%Output folder for retrieved watermarks
retrievedFolder = fullfile(projectRoot, 'data', 'output', 'retrieved');

%Create output folder if it does not exist
if ~exist(retrievedFolder, 'dir')
    mkdir(retrievedFolder);
end

%% DCT retrieval paths

dctInputFolder = fullfile(projectRoot, 'data', 'output', 'attacks', 'dct');
dctJsonPath = fullfile(projectRoot, 'data', 'output', 'dct_metadata.json');

dctInputFiles = {
    'dct_no_attack.png'
    'dct_jpeg_q50.png'
    'dct_gaussian_noise.png'
    'dct_blur_3x3.png'
    'dct_crop80_resize.png'
};

dctOutputFiles = {
    'dct_no_attack_extracted_watermark.png'
    'dct_jpeg_q50_extracted_watermark.png'
    'dct_gaussian_noise_extracted_watermark.png'
    'dct_blur_3x3_extracted_watermark.png'
    'dct_crop80_resize_extracted_watermark.png'
};

%Retrieve all DCT watermarks
for index = 1:length(dctInputFiles)

    inputPath = fullfile(dctInputFolder, dctInputFiles{index});

    outputPath = fullfile(retrievedFolder, dctOutputFiles{index});

    dct_retrieval(inputPath, outputPath, dctJsonPath);
end

%% LSB retrieval paths

lsbInputFolder = fullfile(projectRoot, 'data', 'output', 'attacks', 'lsb');
lsbJsonPath = fullfile(projectRoot, 'data', 'output', 'lsb_metadata.json');

lsbInputFiles = {
    'lsb_no_attack.png'
    'lsb_jpeg_q50.png'
    'lsb_gaussian_noise.png'
    'lsb_blur_3x3.png'
    'lsb_crop80_resize.png'
};

lsbOutputFiles = {
    'lsb_no_attack_extracted_watermark.png'
    'lsb_jpeg_q50_extracted_watermark.png'
    'lsb_gaussian_noise_extracted_watermark.png'
    'lsb_blur_3x3_extracted_watermark.png'
    'lsb_crop80_resize_extracted_watermark.png'
};

numBitsUsed = 6;

%Retrieve all LSB watermarks
for index = 1:length(lsbInputFiles)

    inputPath = fullfile(lsbInputFolder, lsbInputFiles{index});

    outputPath = fullfile(retrievedFolder, lsbOutputFiles{index});

    lsb_retrieve(inputPath, outputPath, numBitsUsed, lsbJsonPath);
end

fprintf('All watermark retrievals complete.\n');
fprintf('Results saved in: %s\n', retrievedFolder);