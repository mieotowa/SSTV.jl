"""
灰度SSTV模式实现
"""
module Grayscale

using ..SSTV
using Images
using ImageCore

"""
灰度SSTV基类
"""
abstract type GrayscaleSSTV <: SSTV.AbstractSSTV end

"""
自适应缩放：保持宽高比，尽可能填满目标尺寸，空白部分填充白色
"""
function adapitve_scaling(img, target_height::Int, target_width::Int)
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
    # 使用Gray(1)创建白色
    if img_type <: Gray
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
处理透明通道：将RGBA图像转换为RGB，透明部分合成到白色背景，然后转换为灰度
"""
function handle_alpha_channel_grayscale(img)
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
        
        # 转换为灰度：Y = 0.299*R + 0.587*G + 0.114*B
        gray_channel = 0.299f0 .* r_composited .+ 0.587f0 .* g_composited .+ 0.114f0 .* b_composited
        
        # 创建灰度图像，确保使用正确的类型
        gray_type = Gray{eltype(gray_channel)}
        gray_img = colorview(gray_type, gray_channel)
        
        return gray_img
    elseif eltype(img) <: Gray
        # 已经是灰度，直接返回
        return img
    elseif eltype(img) <: RGB
        # RGB图像，转换为灰度
        return Gray.(img)
    else
        # 其他类型，尝试转换为灰度
        if ndims(img) == 3
            return Gray.(img)
        else
            return img
        end
    end
end

"""
初始化灰度图像
"""
function init_grayscale!(sstv::GrayscaleSSTV)
    # 处理透明通道（如果有）并转换为灰度
    sstv.image = handle_alpha_channel_grayscale(sstv.image)
    
    # 确保是灰度图像
    if !(eltype(sstv.image) <: Gray)
        sstv.image = Gray.(sstv.image)
    end
    
    # 自适应缩放，保持宽高比
    height = get_height(sstv)
    width = get_width(sstv)
    sstv.image = adapitve_scaling(sstv.image, height, width)
    # 不缓存channelview，而是在需要时调用
    sstv.pixels = nothing  # 占位符，实际不使用
end

"""
生成图像频率元组
"""
function SSTV.gen_image_tuples(sstv::GrayscaleSSTV)
    Channel() do ch
        height = get_height(sstv)
        width = get_width(sstv)
        
        for line in 1:height
            # 水平同步
            for (freq, msec) in SSTV.horizontal_sync(sstv)
                put!(ch, (freq, msec))
            end
            
            # 编码扫描线
            for (freq, msec) in encode_line(sstv, line)
                put!(ch, (freq, msec))
            end
        end
    end
end

"""
编码单行
"""
function encode_line(sstv::GrayscaleSSTV, line::Int)
    Channel() do ch
        width = get_width(sstv)
        scan_time = get_scan_time(sstv)
        msec_pixel = scan_time / width
        
        for col in 1:width
            pixel_value = get_pixel_value(sstv, col, line)
            freq_pixel = SSTV.byte_to_freq(pixel_value)
            put!(ch, (freq_pixel, msec_pixel))
        end
    end
end

"""
获取像素值 - 子类需要实现
"""
function get_pixel_value(sstv::GrayscaleSSTV, col::Int, line::Int)
    error("子类必须实现get_pixel_value方法")
end

"""
获取图像宽度 - 子类需要实现
"""
function get_width(sstv::GrayscaleSSTV)
    error("子类必须实现get_width方法")
end

"""
获取图像高度 - 子类需要实现
"""
function get_height(sstv::GrayscaleSSTV)
    error("子类必须实现get_height方法")
end

"""
获取扫描时间 - 子类需要实现
"""
function get_scan_time(sstv::GrayscaleSSTV)
    error("子类必须实现get_scan_time方法")
end

"""
Robot8BW模式 - 160x120, 60秒
"""
mutable struct Robot8BW <: GrayscaleSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function Robot8BW(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_grayscale!(sstv)
        sstv
    end
end

const VIS_CODE_ROBOT8BW = 0x02
const WIDTH_ROBOT8BW = 160
const HEIGHT_ROBOT8BW = 120
const SYNC_ROBOT8BW = 7.0
const SCAN_ROBOT8BW = 60.0

function SSTV.get_vis_code(sstv::Robot8BW)
    return VIS_CODE_ROBOT8BW
end

function SSTV.get_sync_time(sstv::Robot8BW)
    return SYNC_ROBOT8BW
end

function get_width(sstv::Robot8BW)
    return WIDTH_ROBOT8BW
end

function get_height(sstv::Robot8BW)
    return HEIGHT_ROBOT8BW
end

function get_scan_time(sstv::Robot8BW)
    return SCAN_ROBOT8BW
end

function get_pixel_value(sstv::Robot8BW, col::Int, line::Int)
    # 使用缓存的调整后图像
    # 对于灰度图像，channelview返回2D数组(height, width)，不是3D
    pixels = channelview(sstv.image)
    return UInt8(round(pixels[line, col] * 255))
end

"""
Robot24BW模式 - 320x240, 93秒
"""
mutable struct Robot24BW <: GrayscaleSSTV
    image::AbstractArray
    samples_per_sec::Int
    bits::Int
    vox_enabled::Bool
    fskid_payload::String
    nchannels::Int
    pixels::Union{AbstractArray, Nothing}
    
    function Robot24BW(image, samples_per_sec::Int=11025, bits::Int=16)
        sstv = new(image, samples_per_sec, bits, false, "", 1, nothing)
        init_grayscale!(sstv)
        sstv
    end
end

const VIS_CODE_ROBOT24BW = 0x0A
const WIDTH_ROBOT24BW = 320
const HEIGHT_ROBOT24BW = 240
const SYNC_ROBOT24BW = 7.0
const SCAN_ROBOT24BW = 93.0

function SSTV.get_vis_code(sstv::Robot24BW)
    return VIS_CODE_ROBOT24BW
end

function SSTV.get_sync_time(sstv::Robot24BW)
    return SYNC_ROBOT24BW
end

function get_width(sstv::Robot24BW)
    return WIDTH_ROBOT24BW
end

function get_height(sstv::Robot24BW)
    return HEIGHT_ROBOT24BW
end

function get_scan_time(sstv::Robot24BW)
    return SCAN_ROBOT24BW
end

function get_pixel_value(sstv::Robot24BW, col::Int, line::Int)
    # 使用缓存的调整后图像
    # 对于灰度图像，channelview返回2D数组(height, width)，不是3D
    pixels = channelview(sstv.image)
    return UInt8(round(pixels[line, col] * 255))
end

export Robot8BW, Robot24BW

end
