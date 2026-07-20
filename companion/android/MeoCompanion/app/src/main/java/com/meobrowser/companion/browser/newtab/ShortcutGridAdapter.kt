package com.meobrowser.companion.browser.newtab

import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
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
        val radius = 14f * density

        if (position == items.size) {
            holder.title.text = "添加"
            holder.letter.visibility = View.VISIBLE
            holder.letter.text = "＋"
            holder.letter.setTextColor(0xFF6B7280.toInt())
            holder.letter.background = holder.itemView.context.getDrawable(R.drawable.bg_shortcut_add)
            holder.icon.visibility = View.INVISIBLE
            holder.icon.setImageDrawable(null)
            holder.icon.tag = null
            holder.itemView.setOnClickListener { onAdd() }
            holder.itemView.setOnLongClickListener(null)
            return
        }

        val item = items[position]
        holder.title.text = item.title

        val color = ShortcutIconHelper.colorFor(item.url, item.title)
        val letterBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(color)
        }

        holder.icon.visibility = View.VISIBLE
        holder.icon.setPadding(
            (12 * density).toInt(),
            (12 * density).toInt(),
            (12 * density).toInt(),
            (12 * density).toInt()
        )
        holder.icon.background = letterBg
        holder.icon.setImageDrawable(null)
        holder.icon.scaleType = ImageView.ScaleType.CENTER_CROP

        holder.letter.visibility = View.VISIBLE
        holder.letter.background = letterBg
        holder.letter.setTextColor(ShortcutIconHelper.contrastLetterColor(color))
        holder.letter.text = ShortcutIconHelper.letter(item.title, item.url)

        ShortcutIconHelper.bindFavicon(holder.icon, item) {
            holder.letter.visibility = View.GONE
            holder.icon.setPadding(0, 0, 0, 0)
            // 圆角裁剪：用同色圆角底 + 图标
            holder.icon.background = letterBg
            holder.icon.clipToOutline = true
            holder.icon.outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, radius)
                }
            }
        }

        holder.itemView.setOnClickListener { onOpen(item) }
        holder.itemView.setOnLongClickListener {
            onLong(item)
            true
        }
    }
}
