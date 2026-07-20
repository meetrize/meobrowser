package com.meobrowser.companion.browser.newtab

import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.meobrowser.companion.R

class ShortcutGridAdapter(
    private val items: List<ShortcutItem>,
    private val onOpen: (ShortcutItem) -> Unit,
    private val onLong: (ShortcutItem) -> Unit,
    private val onAdd: () -> Unit
) : RecyclerView.Adapter<ShortcutGridAdapter.VH>() {

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val frame: FrameLayout = view.findViewById(R.id.shortcutIconFrame)
        val icon: ImageView = view.findViewById(R.id.shortcutIcon)
        val letter: TextView = view.findViewById(R.id.shortcutLetter)
        val title: TextView = view.findViewById(R.id.shortcutTitle)
    }

    override fun getItemCount(): Int = items.size + 1

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_shortcut, parent, false)
        return VH(view)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val density = holder.itemView.resources.displayMetrics.density
        val radiusPx = 14f * density
        val insetPad = (9 * density).toInt()

        if (position == items.size) {
            holder.title.text = "添加"
            holder.letter.visibility = View.VISIBLE
            holder.letter.text = "＋"
            holder.letter.setTextColor(0xFF6B7280.toInt())
            holder.letter.setBackgroundResource(0)
            holder.icon.visibility = View.INVISIBLE
            holder.icon.setImageDrawable(null)
            holder.icon.tag = null
            holder.frame.setBackgroundResource(R.drawable.bg_shortcut_add)
            holder.frame.elevation = 3f * density
            holder.itemView.setOnClickListener { onAdd() }
            holder.itemView.setOnLongClickListener(null)
            return
        }

        val item = items[position]
        holder.title.text = item.title

        val color = ShortcutIconHelper.colorFor(item.url, item.title)
        val letterBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radiusPx
            setColor(color)
        }

        holder.frame.elevation = 5f * density
        holder.frame.background = letterBg
        holder.frame.outlineProvider = ViewOutlineProvider.BACKGROUND
        holder.frame.clipToOutline = true

        holder.icon.visibility = View.VISIBLE
        holder.icon.setImageDrawable(null)
        holder.icon.setPadding(0, 0, 0, 0)
        holder.icon.scaleType = ImageView.ScaleType.CENTER_CROP
        holder.icon.background = null

        holder.letter.visibility = View.VISIBLE
        holder.letter.background = null
        holder.letter.setTextColor(ShortcutIconHelper.contrastLetterColor(color))
        holder.letter.text = ShortcutIconHelper.letter(item.title, item.url)

        ShortcutIconHelper.bindFavicon(holder.icon, item) { cached ->
            if (holder.icon.tag != item.id) return@bindFavicon
            holder.letter.visibility = View.GONE
            when (cached.fit) {
                ShortcutIconHelper.FitStyle.INSET -> {
                    // 透明/异形：白底 + 四周留白
                    val white = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = radiusPx
                        setColor(0xFFFFFFFF.toInt())
                    }
                    holder.frame.background = white
                    holder.frame.clipToOutline = true
                    holder.icon.setPadding(insetPad, insetPad, insetPad, insetPad)
                    holder.icon.scaleType = ImageView.ScaleType.FIT_CENTER
                }
                ShortcutIconHelper.FitStyle.FILL -> {
                    // 矩形色块：铺满圆角矩形
                    holder.frame.background = letterBg
                    holder.frame.clipToOutline = true
                    holder.icon.setPadding(0, 0, 0, 0)
                    holder.icon.scaleType = ImageView.ScaleType.CENTER_CROP
                }
            }
            holder.icon.setImageBitmap(cached.bitmap)
        }

        holder.itemView.setOnClickListener { onOpen(item) }
        holder.itemView.setOnLongClickListener {
            onLong(item)
            true
        }
    }
}
