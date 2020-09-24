# CastANet - castanet_activation_mapping.py

""" 
    Implements the Grad-CAM algorithm

"""

import cv2
import cmapy
import keras
import matplotlib
import numpy as np
import tensorflow as tf
from keras import Input
from keras import Model
from keras.layers import Conv2D
from keras.layers import Dense

import castanet_log as cLog
import castanet_config as cConfig

MAPS = []



def initialize(nrows, ncols):
    """ Create blank images for all annotation classes.
        PARAMETERS
        nrows: int
            Tile row count.
        ncols: int
            Tile column count.
    """

    if cConfig.get('generate_cams'):

        # Create an empty image, to be used as template.
        edge = cConfig.get('tile_edge')
        blank = np.zeros((nrows * edge, ncols * edge, 3), np.uint8)

        global MAPS
        
        # Create copies of the template blank image for each class.
        MAPS = [blank.copy() for _ in cConfig.get('header')]



def get_last_conv_model(model):
    """ Map the model input to its last convolutional layer.
        PARAMETERS
        model: Sequential (tensorflow)
            Pre-trained model used for predictions.
        RAISES
        CastANetError
            if the input model does not contain any convolutional layer.
    """

    # The last convolutional layer occurs first on the reversed layer list.
    for layer in reversed(model.layers):

        if isinstance(layer, Conv2D):

            last_conv = layer
            last_conv_model = Model(model.inputs, last_conv.output)

            return (last_conv, last_conv_model)

    # We could not find any convolutional layer in the input model.
    cLog.failwith(f'{model} has no Conv2D layer', cLog.ERR_INVALID_MODEL)



def get_classifier_model(model, last_conv):
    """ Map the output of the last convolutional layer to model predictions.
        PARAMETERS
        model: Sequential (tensorflow)
            Pre-trained model used for predictions.
        last_conv: Conv2D (tensorflow)
            Last convolutional layer of the given model.
    """

    classifier_input = Input(shape=last_conv.output.shape[1:])
    x = classifier_input

    # Index of the last convolutional layer.
    last_index = model.layers.index(last_conv)   
    
    for layer in model.layers[last_index + 1:]:

        x = layer(x)
    
    return Model(classifier_input, x)



def compute_cam(index, tile, last_conv_model, classifier_model):
    """ Compute gradient and class activation map.
        PARAMETERS
        index: int
            Class index.
        tile: numpy.ndarray
            Input tile to be processed.
        last_conv_model: Functional (tensorflow)
            Model to retrieve the output of the last Conv2D layer.
        classifier_model: Functional (tensorflow)
            Model to retrieve the gradients.
    """

    # Transform the tile array into a batch.
    # <tile_batch> shape is (1, model_input_size, model_input_size, 3).
    tile_batch = np.expand_dims(tile, axis=0)

    # Compute the output of the last convolutional layer.
    last_conv_output = last_conv_model(tile_batch)

    with tf.GradientTape(watch_accessed_variables=False) as tape:

        # Watch the gradient.
        tape.watch(last_conv_output)

        # Obtain the predictions.
        predictions = classifier_model(last_conv_output)

        # Build a tensor for the given index
        class_index = tf.convert_to_tensor(index, dtype='int64') 

        # Dtermine whether the index corresponds to the best prediction.
        is_best_match = class_index == tf.argmax(predictions[0])

        # Retrieve the corresponding channel.
        class_channel = predictions[:, class_index]

    # Retrieve the corresponding gradients.
    grads = tape.gradient(class_channel, last_conv_output)

    # Compute the guided gradients.
    cast_conv_outputs = tf.cast(last_conv_output > 0, 'float32')
    cast_grads = tf.cast(grads > 0, 'float32')
    guided_grads = cast_conv_outputs * cast_grads * grads

    # Remove the unnecessary batch dimension from the convolution 
    # and from the guided gradients.
    last_conv_output = last_conv_output[0]
    guided_grads = guided_grads[0]

    # Compute the average of the gradient values, and, using them
    # as weights, compute the ponderation of the filters with
    # respect to the weights.
    weights = tf.reduce_mean(guided_grads, axis=(0, 1))
    cam = tf.reduce_sum(tf.multiply(weights, last_conv_output), axis=-1)

    return (cam, is_best_match)



def make_heatmap(cam, is_best_match, colormap=cv2.COLORMAP_JET):
    """ Generate a heatmap image from a heatmap tensor.
        PARAMETERS
        cam: EagerTensor (tensorflow)
            Class activation map tensor.
        is_best_match: int 
            Tells whether the CAM corresponds to the best prediction.
        colormap: int, optional
            OpenCV colormap to use when <is_best_match> is true.
    """

    # Resize the heatmap to input tile size.
    edge = cConfig.get('tile_edge')
    heatmap = cv2.resize(cam.numpy(), (edge, edge))

    # Normalize heatmap values.
    numer = heatmap - np.min(heatmap)
    denom = heatmap.max() - heatmap.min() + 1e-10 # division by zero
    heatmap = numer / denom
    
    # Convert raw values to 8-bit pixel intensities.
    heatmap = (heatmap * 255).astype('uint8')

    # Apply colormap.
    colormap = colormap if is_best_match else cv2.COLORMAP_BONE
    color_heatmap = cv2.applyColorMap(heatmap, colormap)

    return color_heatmap



def generate(model, row, r):
    """ Generate a mosaic of class activation maps for an array of tiles.
        PARAMETERS
        model: Sequential (tensorflow)
            Pre-trained model used for predictions.
        row: numpy.ndarray
            Row of preprocessed tiles from the large input image.
        r: int
            Row index.
    """

    if cConfig.get('generate_cams'):

        edge = cConfig.get('tile_edge')

        # Map the input tile to the activations of the last Conv2D layer.
        last_conv, last_conv_model = get_last_conv_model(model)

        # Map the activations of <last_conv> to the final class predictions.
        classifier_model = get_classifier_model(model, last_conv)
        
        for c, tile in enumerate(row):

            # Generate class activation maps for all annotations classes
            # The function <compute_cam> returns a boolean which indicates
            # whether the given class is the best match.    
            cams = [compute_cam(i, tile, last_conv_model, classifier_model)
                    for i, _ in enumerate(cConfig.get('header'))]
        

            for (cam, is_best_match), large_map in zip(cams, MAPS):

                # Generats the heatmap.
                heatmap = make_heatmap(cam, is_best_match)

                # Resize the tile to its original size, desaturate
                # and increase the contrast (better overlay rendition).
                resized = np.uint8(cv2.resize(tile, (edge, edge)) * 255)
                resized = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
                resized = cv2.cvtColor(resized, cv2.COLOR_GRAY2BGR)
                resized = cv2.convertScaleAbs(resized, alpha=1.5, beta=0.8)

                # Overlay the heatmap on top of the desaturated tile.
                output = cv2.addWeighted(heatmap, 0.4, resized, 0.6, 0.0)
                output = cv2.cvtColor(output, cv2.COLOR_BGR2RGB)
                
                # Inserts the overlay on the large map.
                rpos = r * edge
                cpos = c * edge
                large_map[rpos:rpos + edge, cpos:cpos + edge] = output           



def retrieve():
    """ Return the class activation map mosaics.
        RETURNS
        CAMS
            if cConfig.get('generate_cams') is set to true.
        None
            otherwise.
    """

    return MAPS if cConfig.get('generate_cams') else None
