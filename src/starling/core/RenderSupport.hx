// =================================================================================================
//
//	Starling Framework
//	Copyright 2011-2014 Gamua. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.core;

import openfl.display3D._shaders.AGLSLShaderUtils;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DProgramType;
import openfl.display3D.Context3DStencilAction;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.Context3DTriangleFace;
import openfl.display3D.Program3D;
import openfl.geom.Matrix;
import openfl.geom.Matrix3D;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.geom.Vector3D;
import openfl.utils.AGALMiniAssembler;
import openfl.Vector;

import starling.display.BlendMode;
import starling.display.DisplayObject;
import starling.display.Quad;
import starling.display.QuadBatch;
import starling.display.Stage;
import starling.errors.MissingContextError;
import starling.textures.Texture;
import starling.textures.TextureSmoothing;
import starling.utils.Color;
import starling.utils.MatrixUtil;
import starling.utils.RectangleUtil;
import starling.utils.SystemUtil;

/** A class that contains helper methods simplifying Stage3D rendering.
 *
 *  A RenderSupport instance is passed to any "render" method of display objects. 
 *  It allows manipulation of the current transformation matrix (similar to the matrix 
 *  manipulation methods of OpenGL 1.x) and other helper methods.
 */
class RenderSupport
{
	// members
	
	private var mProjectionMatrix:Matrix;
	private var mModelViewMatrix:Matrix;
	private var mMvpMatrix:Matrix;
	
	private var mMatrixStack:Array<Matrix>;
	private var mMatrixStackSize:Int;
	
	private var mProjectionMatrix3D:Matrix3D;
	private var mModelViewMatrix3D:Matrix3D;
	private var mMvpMatrix3D:Matrix3D;
	
	private var mMatrixStack3D:Array<Matrix3D>;
	private var mMatrixStack3DSize:Int;

	private var mDrawCount:Int;
	private var mBlendMode:String;
	private var mRenderTarget:Texture;
	
	private var mClipRectStack:Array<Rectangle>;
	private var mClipRectStackSize:Int = 0;
	
	private var mQuadBatches:Array<QuadBatch>;
	private var mCurrentQuadBatchID:Int;

	/** helper objects */
	private static var sPoint:Point = new Point();
	private static var sPoint3D:Vector3D = new Vector3D();
	private static var sClipRect:Rectangle = new Rectangle();
	private static var sBufferRect:Rectangle = new Rectangle();
	private static var sScissorRect:Rectangle = new Rectangle();
	//private static var sAssembler = new AGALMiniAssembler();
	private static var sMatrix3D:Matrix3D = new Matrix3D();
	private static var sMatrixData:Array<Float> = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
	
	public var mvpMatrix(get, null):Matrix;
	public var modelViewMatrix(get, null):Matrix;
	public var projectionMatrix(get, set):Matrix;
	public var mvpMatrix3D(get, null):Matrix3D;
	public var projectionMatrix3D(get, set):Matrix3D;
	public var blendMode(get, set):String;
	public var renderTarget(get, set):Texture;
	public var drawCount(get, null):Int;
	
	// construction
	
	/** Creates a new RenderSupport object with an empty matrix stack. */
	public function new()
	{
		mProjectionMatrix = new Matrix();
		mModelViewMatrix = new Matrix();
		mMvpMatrix = new Matrix();
		mMatrixStack = new Array<Matrix>();
		mMatrixStackSize = 0;
		
		mProjectionMatrix3D = new Matrix3D();
		mModelViewMatrix3D = new Matrix3D();
		mMvpMatrix3D = new Matrix3D();
		mMatrixStack3D = new Array<Matrix3D>();
		mMatrixStack3DSize = 0;
		
		mDrawCount = 0;
		mRenderTarget = null;
		mBlendMode = BlendMode.NORMAL;
		mClipRectStack = new Array<Rectangle>();
		
		mCurrentQuadBatchID = 0;
		mQuadBatches = new Array<QuadBatch>();
		mQuadBatches.push(new QuadBatch());
		
		loadIdentity();
		setProjectionMatrix(0, 0, 400, 300);
	}
	
	/** Disposes all quad batches. */
	public function dispose():Void
	{
		for (quadBatch in mQuadBatches)
			quadBatch.dispose();
	}
	
	// matrix manipulation

	/** Sets up the projection matrices for 2D and 3D rendering.
	 *
	 *  <p>The first 4 parameters define which area of the stage you want to view. The camera
	 *  will 'zoom' to exactly this region. The perspective in which you're looking at the
	 *  stage is determined by the final 3 parameters.</p>
	 *
	 *  <p>The stage is always on the rectangle that is spawned up between x- and y-axis (with
	 *  the given size). All objects that are exactly on that rectangle (z equals zero) will be
	 *  rendered in their true size, without any distortion.</p>
	 */
	public function setProjectionMatrix(x:Float, y:Float, width:Float, height:Float,
										stageWidth:Float=0, stageHeight:Float=0,
										cameraPos:Vector3D=null):Void
	{
		if (stageWidth  <= 0) stageWidth = width;
		if (stageHeight <= 0) stageHeight = height;
		if (cameraPos == null)
		{
			cameraPos = sPoint3D;
			cameraPos.setTo(
				stageWidth / 2, stageHeight / 2,   // -> center of stage
				stageWidth / Math.tan(0.5) * 0.5); // -> fieldOfView = 1.0 rad
		}

		// set up 2d (orthographic) projection
		mProjectionMatrix.setTo(2.0/width, 0, 0, -2.0/height,
			-(2*x + width) / width, (2*y + height) / height);

		var focalLength:Float = Math.abs(cameraPos.z);
		var offsetX:Float = cameraPos.x - stageWidth  / 2;
		var offsetY:Float = cameraPos.y - stageHeight / 2;
		var far:Float    = focalLength * 20;
		var near:Float   = 1;
		var scaleX:Float = stageWidth  / width;
		var scaleY:Float = stageHeight / height;

		// set up general perspective
		sMatrixData[ 0] =  2 * focalLength / stageWidth;  // 0,0
		sMatrixData[ 5] = -2 * focalLength / stageHeight; // 1,1  [negative to invert y-axis]
		sMatrixData[10] =  far / (far - near);            // 2,2
		sMatrixData[14] = -far * near / (far - near);     // 2,3
		sMatrixData[11] =  1;                             // 3,2

		// now zoom in to visible area
		sMatrixData[0] *=  scaleX;
		sMatrixData[5] *=  scaleY;
		sMatrixData[8]  =  scaleX - 1 - 2 * scaleX * (x - offsetX) / stageWidth;
		sMatrixData[9]  = -scaleY + 1 + 2 * scaleY * (y - offsetY) / stageHeight;

		mProjectionMatrix3D.copyRawDataFrom(sMatrixData);
		mProjectionMatrix3D.prependTranslation(
			-stageWidth /2.0 - offsetX,
			-stageHeight/2.0 - offsetY,
			focalLength);

		applyClipRect();
	}

	/** Sets up the projection matrix for ortographic 2D rendering. */
	//[Deprecated(replacement="setProjectionMatrix")] 
	public function setOrthographicProjection(x:Float, y:Float, width:Float, height:Float):Void
	{
		trace("Deprecated, use setProjectionMatrix instead");
		/*var stage:Stage = Starling.current.stage;
		sClipRect.setTo(x, y, width, height);
		setProjectionMatrix(x, y, width, height,
			stage.stageWidth, stage.stageHeight, stage.cameraPosition);*/
		setProjectionMatrix(x, y, width, height);
	}
	
	/** Changes the modelview matrix to the identity matrix. */
	public function loadIdentity():Void
	{
		mModelViewMatrix.identity();
		mModelViewMatrix3D.identity();
	}
	
	/** Prepends a translation to the modelview matrix. */
	public function translateMatrix(dx:Float, dy:Float):Void
	{
		MatrixUtil.prependTranslation(mModelViewMatrix, dx, dy);
	}
	
	/** Prepends a rotation (angle in radians) to the modelview matrix. */
	public function rotateMatrix(angle:Float):Void
	{
		MatrixUtil.prependRotation(mModelViewMatrix, angle);
	}
	
	/** Prepends an incremental scale change to the modelview matrix. */
	public function scaleMatrix(sx:Float, sy:Float):Void
	{
		MatrixUtil.prependScale(mModelViewMatrix, sx, sy);
	}
	
	/** Prepends a matrix to the modelview matrix by multiplying it with another matrix. */
	public function prependMatrix(matrix:Matrix):Void
	{
		MatrixUtil.prependMatrix(mModelViewMatrix, matrix);
	}
	
	/** Prepends translation, scale and rotation of an object to the modelview matrix. */
	public function transformMatrix(object:DisplayObject):Void
	{
		MatrixUtil.prependMatrix(mModelViewMatrix, object.transformationMatrix);
	}
	
	/** Pushes the current modelview matrix to a stack from which it can be restored later. */
	public function pushMatrix():Void
	{
		if (mMatrixStack.length < mMatrixStackSize + 1)
			mMatrixStack.push(new Matrix());
	
		mMatrixStack[Std.int(mMatrixStackSize++)].copyFrom(mModelViewMatrix);
	}
	
	/** Restores the modelview matrix that was last pushed to the stack. */
	public function popMatrix():Void
	{
		mModelViewMatrix.copyFrom(mMatrixStack[Std.int(--mMatrixStackSize)]);
	}
	
	/** Empties the matrix stack, resets the modelview matrix to the identity matrix. */
	public function resetMatrix():Void
	{
		mMatrixStackSize = 0;
		mMatrixStack3DSize = 0;
		loadIdentity();
	}
	
	/** Prepends translation, scale and rotation of an object to a custom matrix. */
	public static function transformMatrixForObject(matrix:Matrix, object:DisplayObject):Void
	{
		MatrixUtil.prependMatrix(matrix, object.transformationMatrix);
	}
	
	/** Calculates the product of modelview and projection matrix. 
	 *  CAUTION: Use with care! Each call returns the same instance. */
	private function get_mvpMatrix():Matrix
	{
		mMvpMatrix.copyFrom(mModelViewMatrix);
		mMvpMatrix.concat(mProjectionMatrix);
		return mMvpMatrix;
	}
	
	/** Returns the current modelview matrix.
	 *  CAUTION: Use with care! Each call returns the same instance. */
	private function get_modelViewMatrix():Matrix { return mModelViewMatrix; }
	
	/** Returns the current projection matrix.
	 *  CAUTION: Use with care! Each call returns the same instance. */
	private function get_projectionMatrix():Matrix { return mProjectionMatrix; }
	public function  set_projectionMatrix(value:Matrix):Matrix 
	{
		mProjectionMatrix.copyFrom(value);
		applyClipRect();
		return value;
	}
	
	// 3d transformations
	
	/** Prepends translation, scale and rotation of an object to the 3D modelview matrix.
	 *  The current contents of the 2D modelview matrix is stored in the 3D modelview matrix
	 *  before doing so; the 2D modelview matrix is then reset to the identity matrix. */
	public function transformMatrix3D(object:DisplayObject):Void
	{
		mModelViewMatrix3D.prepend(MatrixUtil.convertTo3D(mModelViewMatrix, sMatrix3D));
		mModelViewMatrix3D.prepend(object.transformationMatrix3D);
		mModelViewMatrix.identity();
	}
	
	/** Pushes the current 3D modelview matrix to a stack from which it can be restored later. */
	public function pushMatrix3D():Void
	{
		if (mMatrixStack3D.length < mMatrixStack3DSize + 1)
			mMatrixStack3D.push(new Matrix3D());
		
		mMatrixStack3D[Std.int(mMatrixStack3DSize++)].copyFrom(mModelViewMatrix3D);
	}
	
	/** Restores the 3D modelview matrix that was last pushed to the stack. */
	public function popMatrix3D():Void
	{
		mModelViewMatrix3D.copyFrom(mMatrixStack3D[Std.int(--mMatrixStack3DSize)]);
	}
	
	/** Calculates the product of modelview and projection matrix and stores it in a 3D matrix.
	 *  Different to 'mvpMatrix', this also takes 3D transformations into account. 
	 *  CAUTION: Use with care! Each call returns the same instance. */
	private function get_mvpMatrix3D():Matrix3D
	{
		if (mMatrixStack3DSize == 0)
		{
			MatrixUtil.convertTo3D(mvpMatrix, mMvpMatrix3D);
		}
		else
		{
			mMvpMatrix3D.copyFrom(mProjectionMatrix3D);
			mMvpMatrix3D.prepend(mModelViewMatrix3D);
			mMvpMatrix3D.prepend(MatrixUtil.convertTo3D(mModelViewMatrix, sMatrix3D));
		}
		
		return mMvpMatrix3D;
	}
	
	/** Returns the current 3D projection matrix.
	 *  CAUTION: Use with care! Each call returns the same instance. */
	private function get_projectionMatrix3D():Matrix3D { return mProjectionMatrix3D; }
	private function set_projectionMatrix3D(value:Matrix3D):Matrix3D
	{
		mProjectionMatrix3D.copyFrom(value);
		return value;
	}

	// blending
	
	/** Activates the current blend mode on the active rendering context. */
	public function applyBlendMode(premultipliedAlpha:Bool):Void
	{
		setBlendFactors(premultipliedAlpha, mBlendMode);
	}
	
	/** The blend mode to be used on rendering. To apply the factor, you have to manually call
	 *  'applyBlendMode' (because the actual blend factors depend on the PMA mode). */
	private function get_blendMode():String { return mBlendMode; }
	private function set_blendMode(value:String):String
	{
		if (value != BlendMode.AUTO) mBlendMode = value;
		return value;
	}
	
	// render targets
	
	/** The texture that is currently being rendered into, or 'null' to render into the 
	 *  back buffer. If you set a new target, it is immediately activated. */
	private function get_renderTarget():Texture { return mRenderTarget; }
	private function set_renderTarget(target:Texture):Texture 
	{
		setRenderTarget(target);
		return target;
	}

	/** Changes the the current render target.
	 *  @param target       Either a texture or 'null' to render into the back buffer.
	 *  @param antiAliasing Only supported for textures, beginning with AIR 13, and only on
	 *                      Desktop. Values range from 0 (no antialiasing) to 4 (best quality).
	 */
	public function setRenderTarget(target:Texture, antiAliasing:Int=0):Void
	{
		mRenderTarget = target;
		applyClipRect();

		if (target != null)
			Starling.Context.setRenderToTexture(target.base,
					SystemUtil.supportsDepthAndStencil, antiAliasing);
		else
			Starling.Context.setRenderToBackBuffer();
	}
	
	// clipping
	
	/** The clipping rectangle can be used to limit rendering in the current render target to
	 *  a certain area. This method expects the rectangle in stage coordinates. Internally,
	 *  it uses the 'scissorRectangle' of stage3D, which works with pixel coordinates. 
	 *  Any pushed rectangle is intersected with the previous rectangle; the method returns
	 *  that intersection. */ 
	public function pushClipRect(rectangle:Rectangle):Rectangle
	{
		if (mClipRectStack.length < mClipRectStackSize + 1)
			mClipRectStack.push(new Rectangle());
		
		mClipRectStack[mClipRectStackSize].copyFrom(rectangle);
		rectangle = mClipRectStack[mClipRectStackSize];
		
		// intersect with the last pushed clip rect
		if (mClipRectStackSize > 0)
			RectangleUtil.intersect(rectangle, mClipRectStack[mClipRectStackSize-1], 
									rectangle);
		
		++mClipRectStackSize;
		applyClipRect();
		
		// return the intersected clip rect so callers can skip draw calls if it's empty
		return rectangle;
	}
	
	/** Restores the clipping rectangle that was last pushed to the stack. */
	public function popClipRect():Void
	{
		if (mClipRectStackSize > 0)
		{
			--mClipRectStackSize;
			applyClipRect();
		}
	}
	
	/** Updates the context3D scissor rectangle using the current clipping rectangle. This
	 *  method is called automatically when either the render target, the projection matrix,
	 *  or the clipping rectangle changes. */
	public function applyClipRect():Void
	{
		finishQuadBatch();
		
		var context:Context3D = Starling.Context;
		if (context == null) return;
		
		if (mClipRectStackSize > 0)
		{
			var width:Int, height:Int;
			var rect:Rectangle = mClipRectStack[mClipRectStackSize-1];
			
			if (mRenderTarget != null)
			{
				width  = Std.int(mRenderTarget.root.nativeWidth);
				height = Std.int(mRenderTarget.root.nativeHeight);
			}
			else
			{
				width  = Starling.current.backBufferWidth;
				height = Starling.current.backBufferHeight;
			}
			
			// convert to pixel coordinates (matrix transformation ends up in range [-1, 1])
			MatrixUtil.transformCoords(mProjectionMatrix, rect.x, rect.y, sPoint);
			sClipRect.x = (sPoint.x * 0.5 + 0.5) * width;
			sClipRect.y = (0.5 - sPoint.y * 0.5) * height;
			
			MatrixUtil.transformCoords(mProjectionMatrix, rect.right, rect.bottom, sPoint);
			sClipRect.right  = (sPoint.x * 0.5 + 0.5) * width;
			sClipRect.bottom = (0.5 - sPoint.y * 0.5) * height;
			
			sBufferRect.setTo(0, 0, width, height);
			RectangleUtil.intersect(sClipRect, sBufferRect, sScissorRect);
			
			// an empty rectangle is not allowed, so we set it to the smallest possible size
			if (sScissorRect.width < 1 || sScissorRect.height < 1)
				sScissorRect.setTo(0, 0, 1, 1);
			
			context.setScissorRectangle(sScissorRect);
		}
		else
		{
			context.setScissorRectangle(null);
		}
	}

	// stencil masks

	private var mMasks = new Vector<DisplayObject>();

	public function pushMask(mask:DisplayObject):Void
	{
		mMasks[mMasks.length] = mask;

		var context:Context3D = Starling.Context;
		if (context == null) return;

		finishQuadBatch();
		context.setStencilActions(
			Context3DTriangleFace.FRONT_AND_BACK,
			Context3DCompareMode.EQUAL, 
			Context3DStencilAction.INCREMENT_SATURATE
		);
		
		drawMask(mask);
		
		context.setStencilReferenceValue(mMasks.length);
		context.setStencilActions(
			Context3DTriangleFace.FRONT_AND_BACK,
			Context3DCompareMode.EQUAL,
			Context3DStencilAction.KEEP
		);
	}

	public function popMask():Void
	{
		var mask:DisplayObject = mMasks.pop();
		
		var context:Context3D = Starling.Context;
		if (context == null) return;
		
		finishQuadBatch();
		
		context.setStencilActions(
			Context3DTriangleFace.FRONT_AND_BACK,
			Context3DCompareMode.EQUAL,
			Context3DStencilAction.DECREMENT_SATURATE
		);
		
		drawMask(mask);
		
		context.setStencilReferenceValue(mMasks.length);
		context.setStencilActions(
			Context3DTriangleFace.FRONT_AND_BACK,
			Context3DCompareMode.EQUAL,
			Context3DStencilAction.KEEP
		);
	}

	private function drawMask(mask:DisplayObject):Void
	{
		pushMatrix();

		var stage:Stage = mask.stage;
		if (stage != null) mask.getTransformationMatrix(stage, mModelViewMatrix);
		else transformMatrix(mask);

		mask.render(this, 0.0);
		finishQuadBatch();

		popMatrix();
	}

	// optimized quad rendering
	
	/** Adds a quad to the current batch of unrendered quads. If there is a state change,
	 *  all previous quads are rendered at once, and the batch is reset. */
	public function batchQuad(quad:Quad, parentAlpha:Float, texture:Texture=null, smoothing:String=null):Void
	{
		if (mQuadBatches[mCurrentQuadBatchID].isStateChange(quad.tinted, parentAlpha, texture, smoothing, mBlendMode))
		{
			finishQuadBatch();
		}
		
		mQuadBatches[mCurrentQuadBatchID].addQuad(quad, parentAlpha, texture, smoothing, mModelViewMatrix, mBlendMode);
	}
	
	/** Adds a batch of quads to the current batch of unrendered quads. If there is a state 
	 *  change, all previous quads are rendered at once. 
	 *  
	 *  <p>Note that you should call this method only for objects with a small number of quads 
	 *  (we recommend no more than 16). Otherwise, the additional CPU effort will be more
	 *  expensive than what you save by avoiding the draw call.</p> */
	public function batchQuadBatch(quadBatch:QuadBatch, parentAlpha:Float):Void
	{
		if (mQuadBatches[mCurrentQuadBatchID].isStateChange(
			quadBatch.tinted, parentAlpha, quadBatch.texture, quadBatch.smoothing, mBlendMode))
		{
			finishQuadBatch();
		}
		
		mQuadBatches[mCurrentQuadBatchID].addQuadBatch(quadBatch, parentAlpha, 
													   mModelViewMatrix, mBlendMode);
	}
	
	/** Renders the current quad batch and resets it. */
	public function finishQuadBatch():Void
	{
		var currentBatch:QuadBatch = mQuadBatches[mCurrentQuadBatchID];
		
		if (currentBatch.numQuads != 0)
		{
			if (mMatrixStack3DSize == 0)
			{
				currentBatch.renderCustom(mProjectionMatrix3D);
			}
			else
			{
				mMvpMatrix3D.copyFrom(mProjectionMatrix3D);
				mMvpMatrix3D.prepend(mModelViewMatrix3D);
				currentBatch.renderCustom(mMvpMatrix3D);
			}
			
			currentBatch.reset();
			
			++mCurrentQuadBatchID;
			++mDrawCount;
			
			if (mQuadBatches.length <= mCurrentQuadBatchID)
				mQuadBatches.push(new QuadBatch());
		}
	}
	
	/** Resets matrix stack, blend mode, quad batch index, and draw count. */
	public function nextFrame():Void
	{
		resetMatrix();
		trimQuadBatches();

		mMasks.length = 0;
		mCurrentQuadBatchID = 0;
		mBlendMode = BlendMode.NORMAL;
		mDrawCount = 0;
	}

	/** Disposes redundant quad batches if the number of allocated batches is more than
	 *  twice the number of used batches. Only executed when there are at least 16 batches. */
	private function trimQuadBatches():Void
	{
		var numUsedBatches:Int  = mCurrentQuadBatchID + 1;
		var numTotalBatches:Int = mQuadBatches.length;
		
		if (numTotalBatches >= 16 && numTotalBatches > 2*numUsedBatches)
		{
			var numToRemove:Int = numTotalBatches - numUsedBatches;
			for (i in 0...numToRemove)
				mQuadBatches.pop().dispose();
		}
	}
	
	// other helper methods
	
	/** Deprecated. Call 'setBlendFactors' instead. */
	public static function setDefaultBlendFactors(premultipliedAlpha:Bool):Void
	{
		setBlendFactors(premultipliedAlpha);
	}
	
	/** Sets up the blending factors that correspond with a certain blend mode. */
	public static function setBlendFactors(premultipliedAlpha:Bool, blendMode:String="normal"):Void
	{
		var blendFactors:Array<Dynamic> = BlendMode.getBlendFactors(blendMode, premultipliedAlpha); 
		//trace('setBlendFactors(${blendFactors[0]} ${blendFactors[1]}) with blendMode=$blendMode');
		Starling.Context.setBlendFactors(blendFactors[0], blendFactors[1]);
	}
	
	/** Clears the render context with a certain color and alpha value. */
	public static function Clear(rgb:UInt=0, alpha:Float=0.0):Void
	{
		Starling.Context.clear(
			Color.getRed(rgb)   / 255.0, 
			Color.getGreen(rgb) / 255.0, 
			Color.getBlue(rgb)  / 255.0,
			alpha);
	}
	
	/** Clears the render context with a certain color and alpha value. */
	public function clear(rgb:UInt=0, alpha:Float=0.0):Void
	{
		RenderSupport.Clear(rgb, alpha);
	}
	
	/** Assembles fragment- and vertex-shaders, passed as Strings, to a Program3D. If you
	 *  pass a 'resultProgram', it will be uploaded to that program; otherwise, a new program
	 *  will be created on the current Stage3D context. */ 
	public static function assembleAgal(vertexShader:String, fragmentShader:String,
										resultProgram:Program3D=null):Program3D
	{
		if (resultProgram == null) 
		{
			var context:Context3D = Starling.Context;
			if (context == null) throw new MissingContextError();
			resultProgram = context.createProgram();
		}
		
		/*var assembledVertex:Dynamic = sAssembler.assemble(vertexShader);
		var assembledFragment:Dynamic = sAssembler.assemble(fragmentShader);
		
		resultProgram.upload(assembledVertex, assembledFragment);*/
		
		
		var vertexByteCode = AGLSLShaderUtils.createShader(Context3DProgramType.VERTEX, vertexShader);
		var fragmentByteCode = AGLSLShaderUtils.createShader(Context3DProgramType.FRAGMENT, fragmentShader);
		
		resultProgram.upload(vertexByteCode, fragmentByteCode);
		
		return resultProgram;
	}
	
	/** Returns the flags that are required for AGAL texture lookup, 
	 *  including the '&lt;' and '&gt;' delimiters. */
	public static function getTextureLookupFlags(format:Context3DTextureFormat, mipMapping:Bool,
												 repeat:Bool=false,
												 smoothing:String="bilinear"):String
	{
		var options:Array<Dynamic> = ["2d", repeat ? "repeat" : "clamp"];
		
		if (format == Context3DTextureFormat.COMPRESSED)
			options.push("dxt1");
		else if (format == Context3DTextureFormat.COMPRESSED_ALPHA)
			options.push("dxt5");
		
		if (smoothing == TextureSmoothing.NONE) {
			options.push("nearest");
			options.push(mipMapping ? "mipnearest" : "mipnone");
		}
		else if (smoothing == TextureSmoothing.BILINEAR) {
			options.push("linear");
			options.push(mipMapping ? "mipnearest" : "mipnone");
		}
		else {
			options.push("linear");
			options.push(mipMapping ? "miplinear" : "mipnone");
		}
		
		return "<" + options.join("") + ">";
	}
	
	// statistics
	
	/** Raises the draw count by a specific value. Call this method in custom render methods
	 *  to keep the statistics display in sync. */
	public function raiseDrawCount(value:UInt=1):Void { mDrawCount += value; }
	
	/** Indicates the number of stage3D draw calls. */
	private function get_drawCount():Int { return mDrawCount; }
}
