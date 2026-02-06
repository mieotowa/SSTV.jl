"""
彩色SSTV模式实现
"""
module Color

using ..SSTV
using ..Grayscale
using Images
using ImageCore

"""
颜色枚举
"""
@enum ColorEnum red=0 green=1 blue=2

"""
彩色SSTV基类
"""
abstract type ColorSSTV <: Grayscale.GrayscaleSSTV end

"""
自适应缩放：保持宽高比，尽可能填满目标尺寸，空白部分填充白色
"""
function adaptive_scaling(img, target_height::Int, target_width::Int)
    img_height, img_width = size(img)
    
    # 计算缩放比例，选择较小的比例以确保图像完全适合目标尺寸
    scale_h = target_height / img_height
    scale_w = target_width / img_width
    scale = min(scale_h, scale_w)
    
    # 计算缩放后的尺寸
    new_height = Int(round(img_height * scale))
    new_width = Int(round(img_width * scale))
    
    # 缩放图像
    resized_img = imresize(img, (new_height, new_width))
    
    # 计算居中位置
    offset_y = (target_height - new_height) ÷ 2
    offset_x = (target_width - new_width) ÷ 2
    
    # 创建目标尺寸的画布（白色背景），使用与缩放后图像相同的类型
    img_type = eltype(resized_img)
    # 使用RGB(1,1,1)或Gray(1)创建白色
    if img_type <: RGB
        base_type = img_type.parameters[1]  # 提取RGB{T}中的T
        white_color = RGB(base_type(1), base_type(1), base_type(1))
    elseif img_type <: Gray
        base_type = img_type.parameters[1]  # 提取Gray{T}中的T
        white_color = Gray(base_type(1))
    else
        white_color = one(img_type)
    end
    canvas = fill(white_color, target_height, target_width)
    
    # 将缩放后的图像居中放置
    canvas[(offset_y+1):(offset_y+new_height), (offset_x+1):(offset_x+new_width)] = resized_img
    
    return canvas
end

"""
处理透明通道：将RGBA图像转换为RGB，透明部分合成到白色背景
"""
function handle_alpha_channel(img)
    # 检查是否是RGBA图像
    if eltype(img) <: RGBA || eltype(img) <: ARGB
        # 获取通道视图
        channels = channelview(img)
        height, width = size(img)
        
        # 提取alpha通道和RGB通道
        if eltype(img) <: RGBA
            # RGBA: R, G, B, A (channelview顺序)
            r_channel = channels[1, :, :]
            g_channel = channels[2, :, :]
            b_channel = channels[3, :, :]
            alpha_channel = channels[4, :, :]
        else  # ARGB
            # ARGB: A, R, G, B (channelview顺序)
            alpha_channel = channels[1, :, :]
            r_channel = channels[2, :, :]
            g_channel = channels[3, :, :]
            b_channel = channels[4, :, :]
        end
        
        # 将RGBA合成到RGB（alpha混合到白色背景）
        one_val = one(eltype(r_channel))
        r_composited = r_channel .* alpha_channel .+ (one_val .- alpha_channel)
        g_composited = g_channel .* alpha_channel .+ (one_val .- alpha_channel)
        b_composited = b_channel .* alpha_channel .+ (one_val .- alpha_channel)
        
        # 创建RGB图像，使用通道的基础类型
        channel_base_type = eltype(r_composited)
        rgb_img = colorview(RGB{channel_base_type}, r_composited, g_composited, b_composited)
        
        return rgb_img
    elseif eltype(img) <: RGB
        # 已经是RGB，直接返回
        return img
    else
        # 其他类型，尝试转换为RGB
        return RGB.(img)
    end
end

"""
初始化彩色图像
"""
function init_color!(sstv::ColorSSTV)
    # 处理透明通道（如果有）
    sstv.image = handle_alpha_channel(sstv.image)
    
    # 确保是RGB图像
    if !(eltype(sstv.image) <: RGB)
        sstv.image = RGB.(sstv.image)
    end
    
    # 自适应缩放图像，保持宽高比
    height = Grayscale.get_height(sstv)
    width = Grayscale.get_width(sstv)
    sstv.image = adaptive_scaling(sstv.image, height, width)
    # 不缓存channelview，而是在需要时调用
    sstv.pixels = nothing  # 占位符，实际不使用
end

"""
编码单行（彩色）
"""
function Grayscale.encode_line(sstv::ColorSSTV, line::Int)
    Channel() do ch
        width = Grayscale.get_width(sstv)
        scan_time = Grayscale.get_scan_time(sstv)
        msec_pixel = scan_time / width
        color_seq = get_color_sequence(sstv)
        
        for color in color_seq
            # 通道前处理
            for (freq, msec) in before_channel(sstv, color)
                put!(ch, (freq, msec))
            end
            
            # 编码该颜色通道
            for col in 1:width
                pixel = get_pixel_rgb(sstv, col, line)
                color_value = get_color_component(pixel, color)
                freq_pixel = SSTV.byte_to_freq(color_value)
                put!(ch, (freq_pixel, msec_pixel))
            end
            
            # 通道后处理
            for (freq, msec) in after_channel(sstv, color)
                put!(ch, (freq, msec))
            end
        end
    end
end

"""
获取颜色序列 - 子类需要实现
"""
function get_color_sequence(sstv::ColorSSTV)
    error("子类必须实现get_color_sequence方法")
end

"""
通道前处理
"""
function before_channel(sstv::ColorSSTV, color::ColorEnum)
    return []
end

"""
通道后处理
"""
function after_channel(sstv::ColorSSTV, color::ColorEnum)
    return []
end

"""
获取像素RGB值（使用缓存的调整后图像）
"""
function get_pixel_rgb(sstv::ColorSSTV, col::Int, line::Int)
    # 使用缓存的调整后图像，每次调用channelview获取像素
    # channelview返回的维度顺序是 (channels, height, width)
    pixels = channelview(sstv.image)
    r = UInt8(round(pixels[1, line, col] * 255))
    g = UInt8(round(pixels[2, line, col] * 255))
    b = UInt8(round(pixels[3, line, col] * 255))
    return (r, g, b)
end

"""
获取颜色分量
"""
function get_color_component(pixel::Tuple{UInt8, UInt8, UInt8}, color::ColorEnum)
    if color == red
        return pixel[1]
    elseif color == green
        return pixel[2]
    else
        return pixel[3]
    end
end

"""
Martin M1模式 - 320x256, 114秒, RGB顺序: GBR
"""
mutable struct MartinM1 <: ColorSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function MartinM1(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_MARTIN_M1 = 0x2c
const WIDTH_MARTIN_M1 = 320
const HEIGHT_MARTIN_M1 = 256
const SYNC_MARTIN_M1 = 4.862
const SCAN_MARTIN_M1 = 146.432
const INTER_CH_GAP_MARTIN_M1 = 0.572

function SSTV.get_vis_code(sstv::MartinM1)
    return VIS_CODE_MARTIN_M1
end

function SSTV.get_sync_time(sstv::MartinM1)
    return SYNC_MARTIN_M1
end

function Grayscale.get_width(sstv::MartinM1)
    return WIDTH_MARTIN_M1
end

function Grayscale.get_height(sstv::MartinM1)
    return HEIGHT_MARTIN_M1
end

function Grayscale.get_scan_time(sstv::MartinM1)
    return SCAN_MARTIN_M1
end

function get_color_sequence(sstv::MartinM1)
    return [green, blue, red]
end

function before_channel(sstv::MartinM1, color::ColorEnum)
    if color == green
        return [(SSTV.FREQ_BLACK, INTER_CH_GAP_MARTIN_M1)]
    end
    return []
end

function after_channel(sstv::MartinM1, color::ColorEnum)
    return [(SSTV.FREQ_BLACK, INTER_CH_GAP_MARTIN_M1)]
end

function Grayscale.get_pixel_value(sstv::MartinM1, col::Int, line::Int)
    pixel = get_pixel_rgb(sstv, col, line)
    return pixel[2]  # 默认返回绿色分量
end

"""
Martin M2模式 - 160x256, 58秒
"""
mutable struct MartinM2 <: ColorSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function MartinM2(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_MARTIN_M2 = 0x28
const WIDTH_MARTIN_M2 = 160
const SCAN_MARTIN_M2 = 73.216

function SSTV.get_vis_code(sstv::MartinM2)
    return VIS_CODE_MARTIN_M2
end

function SSTV.get_sync_time(sstv::MartinM2)
    return SYNC_MARTIN_M1
end

function Grayscale.get_width(sstv::MartinM2)
    return WIDTH_MARTIN_M2
end

function Grayscale.get_height(sstv::MartinM2)
    return HEIGHT_MARTIN_M1
end

function Grayscale.get_scan_time(sstv::MartinM2)
    return SCAN_MARTIN_M2
end

function get_color_sequence(sstv::MartinM2)
    return [green, blue, red]
end

function before_channel(sstv::MartinM2, color::ColorEnum)
    if color == green
        return [(SSTV.FREQ_BLACK, INTER_CH_GAP_MARTIN_M1)]
    end
    return []
end

function after_channel(sstv::MartinM2, color::ColorEnum)
    return [(SSTV.FREQ_BLACK, INTER_CH_GAP_MARTIN_M1)]
end

function Grayscale.get_pixel_value(sstv::MartinM2, col::Int, line::Int)
    pixel = get_pixel_rgb(sstv, col, line)
    return pixel[2]
end

"""
Scottie S1模式 - 320x256, 110秒
"""
mutable struct ScottieS1 <: ColorSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function ScottieS1(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_SCOTTIE_S1 = 0x3c
const SYNC_SCOTTIE_S1 = 9.0
const INTER_CH_GAP_SCOTTIE_S1 = 1.5
const SCAN_SCOTTIE_S1 = 138.24 - INTER_CH_GAP_SCOTTIE_S1

function SSTV.get_vis_code(sstv::ScottieS1)
    return VIS_CODE_SCOTTIE_S1
end

function SSTV.get_sync_time(sstv::ScottieS1)
    return SYNC_SCOTTIE_S1
end

function Grayscale.get_width(sstv::ScottieS1)
    return WIDTH_MARTIN_M1
end

function Grayscale.get_height(sstv::ScottieS1)
    return HEIGHT_MARTIN_M1
end

function Grayscale.get_scan_time(sstv::ScottieS1)
    return SCAN_SCOTTIE_S1
end

function get_color_sequence(sstv::ScottieS1)
    return [red, green, blue]
end

function SSTV.horizontal_sync(sstv::ScottieS1)
    return []  # Scottie模式不使用水平同步
end

function before_channel(sstv::ScottieS1, color::ColorEnum)
    if color == red
        # 只在红色通道前添加同步（使用Martin M1的同步时间）
        return [(SSTV.FREQ_SYNC, SYNC_MARTIN_M1)]
    end
    return [(SSTV.FREQ_BLACK, INTER_CH_GAP_SCOTTIE_S1)]
end

function after_channel(sstv::ScottieS1, color::ColorEnum)
    return []
end

function Grayscale.get_pixel_value(sstv::ScottieS1, col::Int, line::Int)
    pixel = get_pixel_rgb(sstv, col, line)
    return pixel[1]
end

"""
Scottie S2模式 - 160x256, 71秒
"""
mutable struct ScottieS2 <: ColorSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function ScottieS2(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_SCOTTIE_S2 = 0x38
const SCAN_SCOTTIE_S2 = 88.064 - INTER_CH_GAP_SCOTTIE_S1

function SSTV.get_vis_code(sstv::ScottieS2)
    return VIS_CODE_SCOTTIE_S2
end

function SSTV.get_sync_time(sstv::ScottieS2)
    return SYNC_SCOTTIE_S1
end

function Grayscale.get_width(sstv::ScottieS2)
    return WIDTH_MARTIN_M2
end

function Grayscale.get_height(sstv::ScottieS2)
    return HEIGHT_MARTIN_M1
end

function Grayscale.get_scan_time(sstv::ScottieS2)
    return SCAN_SCOTTIE_S2
end

function get_color_sequence(sstv::ScottieS2)
    return [red, green, blue]
end

function SSTV.horizontal_sync(sstv::ScottieS2)
    return []
end

function before_channel(sstv::ScottieS2, color::ColorEnum)
    if color == red
        # 只在红色通道前添加同步（使用Martin M1的同步时间）
        return [(SSTV.FREQ_SYNC, SYNC_MARTIN_M1)]
    end
    return [(SSTV.FREQ_BLACK, INTER_CH_GAP_SCOTTIE_S1)]
end

function after_channel(sstv::ScottieS2, color::ColorEnum)
    return []
end

function Grayscale.get_pixel_value(sstv::ScottieS2, col::Int, line::Int)
    pixel = get_pixel_rgb(sstv, col, line)
    return pixel[1]
end

"""
Robot36模式 - 320x240, YCbCr编码
"""
mutable struct Robot36 <: ColorSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    yuv::Union{AbstractArray, Nothing}
    
    function Robot36(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing, nothing)
        init_color!(sstv)
        # yuv字段将在encode_line中动态计算，这里不需要预先转换
        sstv
    end
end

const VIS_CODE_ROBOT36 = 0x08
const WIDTH_ROBOT36 = 320
const HEIGHT_ROBOT36 = 240
const SYNC_ROBOT36 = 9.0
const INTER_CH_GAP_ROBOT36 = 4.5
const Y_SCAN_ROBOT36 = 88.0
const C_SCAN_ROBOT36 = 44.0
const PORCH_ROBOT36 = 1.5
const SYNC_PORCH_ROBOT36 = 3.0

function SSTV.get_vis_code(sstv::Robot36)
    return VIS_CODE_ROBOT36
end

function SSTV.get_sync_time(sstv::Robot36)
    return SYNC_ROBOT36
end

function Grayscale.get_width(sstv::Robot36)
    return WIDTH_ROBOT36
end

function Grayscale.get_height(sstv::Robot36)
    return HEIGHT_ROBOT36
end

function Grayscale.get_scan_time(sstv::Robot36)
    return Y_SCAN_ROBOT36 + C_SCAN_ROBOT36
end

"""
RGB到YCbCr转换（手动实现）
"""
function rgb_to_ycbcr(r::Float32, g::Float32, b::Float32)
    # 标准RGB到YCbCr转换公式
    y = 0.299f0 * r + 0.587f0 * g + 0.114f0 * b
    cb = -0.168736f0 * r - 0.331264f0 * g + 0.5f0 * b + 0.5f0
    cr = 0.5f0 * r - 0.418688f0 * g - 0.081312f0 * b + 0.5f0
    return (y, cb, cr)
end

function Grayscale.encode_line(sstv::Robot36, line::Int)
    Channel() do ch
        width = Grayscale.get_width(sstv)
        height = Grayscale.get_height(sstv)
        
        # 使用缓存的调整后图像
        rgb_channels = channelview(sstv.image)
        
        # 转换为YCbCr并获取像素
        pixels = []
        for col in 1:width
            r = Float32(rgb_channels[1, line, col])
            g = Float32(rgb_channels[2, line, col])
            b = Float32(rgb_channels[3, line, col])
            y, cb, cr = rgb_to_ycbcr(r, g, b)
            push!(pixels, (y, cb, cr))
        end
        
        channel = 2 - (line % 2)  # 交替使用Cb和Cr (1=Cb, 2=Cr)
        y_pixel_time = Y_SCAN_ROBOT36 / width
        uv_pixel_time = C_SCAN_ROBOT36 / width
        
        # 同步前廊
        put!(ch, (SSTV.FREQ_BLACK, SYNC_PORCH_ROBOT36))
        
        # Y通道
        for p in pixels
            y_val = UInt8(round(clamp(p[1], 0.0f0, 1.0f0) * 255))
            put!(ch, (SSTV.byte_to_freq(y_val), y_pixel_time))
        end
        
        # 通道间频率
        inter_freqs = [nothing, SSTV.FREQ_WHITE, SSTV.FREQ_BLACK]
        put!(ch, (inter_freqs[channel + 1], INTER_CH_GAP_ROBOT36))
        put!(ch, (SSTV.FREQ_VIS_START, PORCH_ROBOT36))
        
        # Cb或Cr通道 (channel=1时为Cb, channel=2时为Cr)
        for p in pixels
            uv_val = UInt8(round(clamp(p[channel + 1], 0.0f0, 1.0f0) * 255))
            put!(ch, (SSTV.byte_to_freq(uv_val), uv_pixel_time))
        end
    end
end

function Grayscale.get_pixel_value(sstv::Robot36, col::Int, line::Int)
    # 使用缓存的调整后图像
    rgb_channels = channelview(sstv.image)
    r = Float32(rgb_channels[1, line, col])
    g = Float32(rgb_channels[2, line, col])
    b = Float32(rgb_channels[3, line, col])
    y, _, _ = rgb_to_ycbcr(r, g, b)
    return UInt8(round(clamp(y, 0.0f0, 1.0f0) * 255))
end

"""
PD模式基类 - 使用YCbCr编码，每次处理两行
"""
abstract type PDSSTV <: ColorSSTV end

"""
PD模式生成图像频率元组 - 每次处理两行
"""
function SSTV.gen_image_tuples(sstv::PDSSTV)
    Channel() do ch
        height = Grayscale.get_height(sstv)
        width = Grayscale.get_width(sstv)
        
        # 使用缓存的调整后图像
        rgb_channels = channelview(sstv.image)
        
        # 每次处理两行
        for line in 1:2:height-1
            # 水平同步
            for (freq, msec) in SSTV.horizontal_sync(sstv)
                put!(ch, (freq, msec))
            end
            
            # 后廊（黑色）
            porch_time = get_porch_time(sstv)
            put!(ch, (SSTV.FREQ_BLACK, porch_time))
            
            # 获取两行的像素
            pixels0 = []
            pixels1 = []
            for col in 1:width
                r0 = Float32(rgb_channels[1, line, col])
                g0 = Float32(rgb_channels[2, line, col])
                b0 = Float32(rgb_channels[3, line, col])
                y0, cb0, cr0 = rgb_to_ycbcr(r0, g0, b0)
                push!(pixels0, (y0, cb0, cr0))
                
                r1 = Float32(rgb_channels[1, line+1, col])
                g1 = Float32(rgb_channels[2, line+1, col])
                b1 = Float32(rgb_channels[3, line+1, col])
                y1, cb1, cr1 = rgb_to_ycbcr(r1, g1, b1)
                push!(pixels1, (y1, cb1, cr1))
            end
            
            pixel_time = get_pixel_time(sstv)
            
            # 第一行的Y通道
            for p in pixels0
                y_val = UInt8(round(clamp(p[1], 0.0f0, 1.0f0) * 255))
                put!(ch, (SSTV.byte_to_freq(y_val), pixel_time))
            end
            
            # 两行的Cr平均值 (R-Y, 红色色差)
            for (p0, p1) in zip(pixels0, pixels1)
                cr_avg = (p0[3] + p1[3]) / 2.0f0
                cr_val = UInt8(round(clamp(cr_avg, 0.0f0, 1.0f0) * 255))
                put!(ch, (SSTV.byte_to_freq(cr_val), pixel_time))
            end
            
            # 两行的Cb平均值 (B-Y, 蓝色色差)
            for (p0, p1) in zip(pixels0, pixels1)
                cb_avg = (p0[2] + p1[2]) / 2.0f0
                cb_val = UInt8(round(clamp(cb_avg, 0.0f0, 1.0f0) * 255))
                put!(ch, (SSTV.byte_to_freq(cb_val), pixel_time))
            end
            
            # 第二行的Y通道
            for p in pixels1
                y_val = UInt8(round(clamp(p[1], 0.0f0, 1.0f0) * 255))
                put!(ch, (SSTV.byte_to_freq(y_val), pixel_time))
            end
        end
    end
end

"""
获取后廊时间 - 子类需要实现
"""
function get_porch_time(sstv::PDSSTV)
    error("子类必须实现get_porch_time方法")
end

"""
获取像素时间 - 子类需要实现
"""
function get_pixel_time(sstv::PDSSTV)
    error("子类必须实现get_pixel_time方法")
end

"""
PD90模式 - 320x256
"""
mutable struct PD90 <: PDSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function PD90(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_PD90 = 0x63
const WIDTH_PD90 = 320
const HEIGHT_PD90 = 256
const SYNC_PD90 = 20.0
const PORCH_PD90 = 2.08
const PIXEL_PD90 = 0.532

function SSTV.get_vis_code(sstv::PD90)
    return VIS_CODE_PD90
end

function SSTV.get_sync_time(sstv::PD90)
    return SYNC_PD90
end

function Grayscale.get_width(sstv::PD90)
    return WIDTH_PD90
end

function Grayscale.get_height(sstv::PD90)
    return HEIGHT_PD90
end

function get_porch_time(sstv::PD90)
    return PORCH_PD90
end

function get_pixel_time(sstv::PD90)
    return PIXEL_PD90
end

function Grayscale.get_scan_time(sstv::PD90)
    # PD模式不使用标准的scan_time
    return 0.0
end

function Grayscale.get_pixel_value(sstv::PD90, col::Int, line::Int)
    # 使用缓存的调整后图像
    rgb_channels = channelview(sstv.image)
    r = Float32(rgb_channels[1, line, col])
    g = Float32(rgb_channels[2, line, col])
    b = Float32(rgb_channels[3, line, col])
    y, _, _ = rgb_to_ycbcr(r, g, b)
    return UInt8(round(clamp(y, 0.0f0, 1.0f0) * 255))
end

"""
PD120模式 - 640x496
"""
mutable struct PD120 <: PDSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function PD120(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_PD120 = 0x5f
const WIDTH_PD120 = 640
const HEIGHT_PD120 = 496
const SYNC_PD120 = 20.0
const PORCH_PD120 = 2.08
const PIXEL_PD120 = 0.19

function SSTV.get_vis_code(sstv::PD120)
    return VIS_CODE_PD120
end

function SSTV.get_sync_time(sstv::PD120)
    return SYNC_PD120
end

function Grayscale.get_width(sstv::PD120)
    return WIDTH_PD120
end

function Grayscale.get_height(sstv::PD120)
    return HEIGHT_PD120
end

function get_porch_time(sstv::PD120)
    return PORCH_PD120
end

function get_pixel_time(sstv::PD120)
    return PIXEL_PD120
end

function Grayscale.get_scan_time(sstv::PD120)
    return 0.0
end

function Grayscale.get_pixel_value(sstv::PD120, col::Int, line::Int)
    # 使用缓存的调整后图像
    rgb_channels = channelview(sstv.image)
    r = Float32(rgb_channels[1, line, col])
    g = Float32(rgb_channels[2, line, col])
    b = Float32(rgb_channels[3, line, col])
    y, _, _ = rgb_to_ycbcr(r, g, b)
    return UInt8(round(clamp(y, 0.0f0, 1.0f0) * 255))
end

"""
PD160模式 - 512x400
"""
mutable struct PD160 <: PDSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function PD160(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_PD160 = 0x62
const WIDTH_PD160 = 512
const HEIGHT_PD160 = 400
const SYNC_PD160 = 20.0
const PORCH_PD160 = 2.08
const PIXEL_PD160 = 0.382

function SSTV.get_vis_code(sstv::PD160)
    return VIS_CODE_PD160
end

function SSTV.get_sync_time(sstv::PD160)
    return SYNC_PD160
end

function Grayscale.get_width(sstv::PD160)
    return WIDTH_PD160
end

function Grayscale.get_height(sstv::PD160)
    return HEIGHT_PD160
end

function get_porch_time(sstv::PD160)
    return PORCH_PD160
end

function get_pixel_time(sstv::PD160)
    return PIXEL_PD160
end

function Grayscale.get_scan_time(sstv::PD160)
    return 0.0
end

function Grayscale.get_pixel_value(sstv::PD160, col::Int, line::Int)
    # 使用缓存的调整后图像
    rgb_channels = channelview(sstv.image)
    r = Float32(rgb_channels[1, line, col])
    g = Float32(rgb_channels[2, line, col])
    b = Float32(rgb_channels[3, line, col])
    y, _, _ = rgb_to_ycbcr(r, g, b)
    return UInt8(round(clamp(y, 0.0f0, 1.0f0) * 255))
end

"""
PD180模式 - 640x496 (继承自PD120)
"""
mutable struct PD180 <: PDSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function PD180(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_PD180 = 0x60
const PIXEL_PD180 = 0.286

function SSTV.get_vis_code(sstv::PD180)
    return VIS_CODE_PD180
end

function SSTV.get_sync_time(sstv::PD180)
    return SYNC_PD120
end

function Grayscale.get_width(sstv::PD180)
    return WIDTH_PD120
end

function Grayscale.get_height(sstv::PD180)
    return HEIGHT_PD120
end

function get_porch_time(sstv::PD180)
    return PORCH_PD120
end

function get_pixel_time(sstv::PD180)
    return PIXEL_PD180
end

function Grayscale.get_scan_time(sstv::PD180)
    return 0.0
end

function Grayscale.get_pixel_value(sstv::PD180, col::Int, line::Int)
    # 使用缓存的调整后图像
    rgb_channels = channelview(sstv.image)
    r = Float32(rgb_channels[1, line, col])
    g = Float32(rgb_channels[2, line, col])
    b = Float32(rgb_channels[3, line, col])
    y, _, _ = rgb_to_ycbcr(r, g, b)
    return UInt8(round(clamp(y, 0.0f0, 1.0f0) * 255))
end

"""
PD240模式 - 640x496 (继承自PD120)
"""
mutable struct PD240 <: PDSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function PD240(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_PD240 = 0x61
const PIXEL_PD240 = 0.382

function SSTV.get_vis_code(sstv::PD240)
    return VIS_CODE_PD240
end

function SSTV.get_sync_time(sstv::PD240)
    return SYNC_PD120
end

function Grayscale.get_width(sstv::PD240)
    return WIDTH_PD120
end

function Grayscale.get_height(sstv::PD240)
    return HEIGHT_PD120
end

function get_porch_time(sstv::PD240)
    return PORCH_PD120
end

function get_pixel_time(sstv::PD240)
    return PIXEL_PD240
end

function Grayscale.get_scan_time(sstv::PD240)
    return 0.0
end

function Grayscale.get_pixel_value(sstv::PD240, col::Int, line::Int)
    # 使用缓存的调整后图像
    rgb_channels = channelview(sstv.image)
    r = Float32(rgb_channels[1, line, col])
    g = Float32(rgb_channels[2, line, col])
    b = Float32(rgb_channels[3, line, col])
    y, _, _ = rgb_to_ycbcr(r, g, b)
    return UInt8(round(clamp(y, 0.0f0, 1.0f0) * 255))
end

"""
PD290模式 - 800x616 (继承自PD240)
"""
mutable struct PD290 <: PDSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function PD290(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_color!(sstv)
        sstv
    end
end

const VIS_CODE_PD290 = 0x5e
const WIDTH_PD290 = 800
const HEIGHT_PD290 = 616
const PIXEL_PD290 = 0.286

function SSTV.get_vis_code(sstv::PD290)
    return VIS_CODE_PD290
end

function SSTV.get_sync_time(sstv::PD290)
    return SYNC_PD120
end

function Grayscale.get_width(sstv::PD290)
    return WIDTH_PD290
end

function Grayscale.get_height(sstv::PD290)
    return HEIGHT_PD290
end

function get_porch_time(sstv::PD290)
    return PORCH_PD120
end

function get_pixel_time(sstv::PD290)
    return PIXEL_PD290
end

function Grayscale.get_scan_time(sstv::PD290)
    return 0.0
end

function Grayscale.get_pixel_value(sstv::PD290, col::Int, line::Int)
    # 使用缓存的调整后图像
    rgb_channels = channelview(sstv.image)
    r = Float32(rgb_channels[1, line, col])
    g = Float32(rgb_channels[2, line, col])
    b = Float32(rgb_channels[3, line, col])
    y, _, _ = rgb_to_ycbcr(r, g, b)
    return UInt8(round(clamp(y, 0.0f0, 1.0f0) * 255))
end

export MartinM1, MartinM2, ScottieS1, ScottieS2, Robot36
export PD90, PD120, PD160, PD180, PD240, PD290
export ColorEnum, red, green, blue

end
