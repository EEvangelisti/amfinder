# CastANet - castanet_predict.py

import os
import pyvips
import numpy as np
import pandas as pd

import castanet_log as cLog
import castanet_save as cSave
import castanet_model as cModel
import castanet_config as cConfig
import castanet_segmentation as cSegm
import castanet_activation_mapping as cMapping



def normalize(t):
    """ Simple normalization function. """

    return t / 255.0



def row_wise_processing(image, nrows, ncols, model):
    """ Predict mycorrhizal structures row by row. 
        PARAMETERS
        image: pyvips.vimage.Image
            Large image (mosaic) from which tiles are extracted.
        nrows: int
            Tile count on Y axis (image height).
        ncols: int
            Tile count on X axis (image width).
        model: Sequential (tensorflow).
            Model used to predict mycorrhizal structures.
    """

    # Creates the images to save the class activation maps.
    cams = cMapping.initialize(nrows, ncols)

    bs = cConfig.get('batch_size')
    c_range = range(ncols)

    # Full row processing, from tile extraction to structure prediction.
    def process_row(r):
        # First, extract all tiles within a row.
        row = [cSegm.tile(image, r, c) for c in c_range]
        # Convert to NumPy array, and normalize.
        row = normalize(np.array(row, np.float32))
        # Predict mycorrhizal structures.
        prd = model.predict(row, batch_size=bs)
        # Retrieve class activation maps.
        cMapping.generate(cams, model, row, r)
        # Update the progress bar.
        cLog.progress_bar(r + 1, nrows)
        # Return prediction as Pandas data frame.
        return pd.DataFrame(prd)

    # Initialize the progress bar.
    cLog.progress_bar(0, nrows)

    # Retrieve predictions for all rows within the image.
    results = [process_row(r) for r in range(nrows)]

    # Concat to a single Pandas dataframe and add header.
    table = pd.concat(results, ignore_index=True)
    table.columns = cConfig.get('header')

    # Add row and column indexes to the Pandas data frame.
    # col_values = 0, 1, ..., c, 0, ..., c, ..., 0, ..., c; c = ncols - 1
    col_values = list(range(ncols)) * nrows
    # row_values = 0, 0, ..., 0, 1, ..., 1, ..., r, ..., r; r = nrows - 1
    row_values = [x // ncols for x in range(nrows * ncols)]
    table.insert(0, column='col', value=col_values)
    table.insert(0, column='row', value=row_values)

    return (table, cams)



def run(input_images):
    """ Run prediction on a bunch of images.
        PARAMETER
        input_images: list 
            Images on which to predict mycorrhizal structures.
    """

    model = cModel.load()
    edge = cConfig.get('tile_edge')

    for path in input_images:

        base = os.path.basename(path)
        print(f'* Image {base}')

        image = pyvips.Image.new_from_file(path, access='random')

        nrows = image.height // edge
        ncols = image.width // edge

        if nrows == 0 or ncols == 0:

            cLog.warning('Tile size ({edge} pixels) is too large')
            continue
            
        else:

            table, cams = row_wise_processing(image, nrows, ncols, model)

            # Save predictions (<table>) and class activations maps (<cams>)
            # in a ZIP archive derived from the image name (<path>). 
            cSave.prediction_table(table, cams, path)