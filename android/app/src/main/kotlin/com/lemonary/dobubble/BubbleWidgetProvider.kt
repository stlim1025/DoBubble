package com.lemonary.dobubble

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject

class BubbleWidgetProviderSmall : BubbleWidgetProvider()
class BubbleWidgetProviderMedium : BubbleWidgetProvider()
class BubbleWidgetProviderLarge : BubbleWidgetProvider()

open class BubbleWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.bubble_widget)

            // Get widget options to determine size
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)

            // Determine which snapshot to use
            // Small: 2x2 (~110dp x 110dp)
            // Medium: 4x2 (~220dp x 110dp)
            // Large: 4x4 (~220dp x 220dp)
            // Determine which snapshot to use based on the class type
            val snapshotKey = when (this) {
                is BubbleWidgetProviderSmall -> "snapshot_small"
                is BubbleWidgetProviderMedium -> "snapshot_medium"
                is BubbleWidgetProviderLarge -> "snapshot_large"
                else -> "snapshot_small"
            }

            val imagePath = widgetData.getString(snapshotKey, null)
            if (imagePath != null) {
                try {
                    val bitmap = android.graphics.BitmapFactory.decodeFile(imagePath)
                    if (bitmap != null) {
                        views.setImageViewBitmap(R.id.widget_image, bitmap)
                        views.setViewVisibility(R.id.widget_footer, View.GONE)
                    } else {
                        // Fallback
                        val total = widgetData.getInt("total_bubbles", 0)
                        val remaining = widgetData.getInt("remaining_bubbles", 0)
                        views.setTextViewText(R.id.widget_progress, "$remaining / $total")
                        views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            } else {
                val total = widgetData.getInt("total_bubbles", 0)
                val remaining = widgetData.getInt("remaining_bubbles", 0)
                views.setTextViewText(R.id.widget_progress, "$remaining / $total")
                views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
            }

            // Handle Clickable Slots
            val bubbleIdsStr = widgetData.getString("bubble_ids", "")
            val bubbleIds = if (bubbleIdsStr.isNullOrEmpty()) emptyList<String>() else bubbleIdsStr.split(",")
            
            if (snapshotKey == "snapshot_small") {
                views.setViewVisibility(R.id.list_container, View.VISIBLE)
                views.setViewVisibility(R.id.grid_container, View.GONE)
                
                for (i in 0 until 4) {
                    val slotId = context.resources.getIdentifier("list_slot_$i", "id", context.packageName)
                    if (slotId != 0) {
                        if (i < bubbleIds.size) {
                            views.setViewVisibility(slotId, View.VISIBLE)
                            val intent = es.antonborri.home_widget.HomeWidgetBackgroundIntent.getBroadcast(
                                context,
                                android.net.Uri.parse("dopop://popbubble?id=${bubbleIds[i]}")
                            )
                            views.setOnClickPendingIntent(slotId, intent)
                        } else {
                            views.setViewVisibility(slotId, View.GONE)
                        }
                    }
                }
            } else {
                views.setViewVisibility(R.id.list_container, View.GONE)
                views.setViewVisibility(R.id.grid_container, View.VISIBLE)
                
                // 1. 모든 슬롯 초기화
                for (i in 0 until 9) {
                    val slotId = context.resources.getIdentifier("grid_slot_$i", "id", context.packageName)
                    if (slotId != 0) {
                        views.setViewVisibility(slotId, View.GONE)
                    }
                }

                // 2. 슬롯에 순차적으로 비눗방울 배치 (HomeWidgetView의 그리드 순서와 일치)
                val maxBubbles = if (snapshotKey == "snapshot_large") 9 else 6
                val bubblesToDisplay = if (bubbleIds.size > maxBubbles) maxBubbles else bubbleIds.size
                
                for (i in 0 until bubblesToDisplay) {
                    val slotId = context.resources.getIdentifier("grid_slot_$i", "id", context.packageName)
                    if (slotId != 0) {
                        val bubbleId = bubbleIds[i]
                        if (bubbleId.isNotEmpty()) {
                            views.setViewVisibility(slotId, View.VISIBLE)
                            val intent = es.antonborri.home_widget.HomeWidgetBackgroundIntent.getBroadcast(
                                context,
                                android.net.Uri.parse("dopop://popbubble?id=$bubbleId")
                            )
                            views.setOnClickPendingIntent(slotId, intent)
                        } else {
                            views.setViewVisibility(slotId, View.GONE)
                        }
                    }
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
