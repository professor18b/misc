package com.squarevalley.i8birdies.improve.aicoach.detection

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import com.osmapps.golf.common.bean.domain.practice2.drawing.SkeletonCanvas

/**
 * @author wulei
 **/
class SkeletonCanvasImp(private val canvas: Canvas) : SkeletonCanvas {

    private val paint = Paint()

    override fun setColor(r: Int, g: Int, b: Int, a: Int) {
        paint.color = Color.argb(a, r, g, b)
    }

    override fun setStroke(stroke: Float) {
        paint.strokeWidth = stroke
    }

    override fun drawLine(x1: Int, y1: Int, x2: Int, y2: Int) {
        canvas.drawLine(x1.toFloat(), y1.toFloat(), x2.toFloat(), y2.toFloat(), paint)
    }

    override fun drawPoint(x: Int, y: Int, stroke: Float) {
        paint.strokeWidth = stroke
        canvas.drawPoint(x.toFloat(), y.toFloat(), paint)
    }

    override fun drawCircle(x: Int, y: Int, stroke: Float) {
        TODO("Not yet implemented")
    }

    override fun drawSquare(x: Int, y: Int, width: Float, height: Float) {
        canvas.drawRect(x.toFloat(), y.toFloat(), x + width, y + height, paint)
    }
}