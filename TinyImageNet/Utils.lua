require "torch"
require "image"

-- convert rgb to grayscale by averaging channel intensities
function rgb2gray(im)
	-- Image.rgb2y uses a different weight mixture

	local dim, w, h = im:size()[1], im:size()[2], im:size()[3]
	if dim ~= 3 then
		 print('<error> expected 3 channels')
		 return im
	end

	-- a cool application of tensor:select
	local r = im:select(1, 1)
	local g = im:select(1, 2)
	local b = im:select(1, 3)

	local z = torch.Tensor(w, h):zero()

	-- z = z + 0.21r
	z = z:add(0.21, r)
	z = z:add(0.72, g)
	z = z:add(0.07, b)
	return z
end

-- convert grayscale to 3 channel rgb image 
function gray2rgb(grayim)

	-- Creating a local tensor variable
	width = grayim:size()[1]
	height = grayim:size()[2]
	local im = torch.Tensor(3, width, height)
	-- Initializing each channel to a gray channel
	im[1] = grayim
	im[2] = grayim
	im[3] = grayim

	return im
end


function create_yuv_images(images)
    local yuv_temp = image.rgb2yuv(images[1]);
    yuv_temp = image.scale(yuv_temp,28,28,'bilinear')
    local uv_temp = yuv_temp[{{2,3}}]
    local y_temp = yuv_temp[{{1}}]
    uv_temp = uv_temp:reshape(1,uv_temp:size()[1], uv_temp:size()[2], uv_temp:size()[3] );
    y_temp = y_temp:reshape(1,y_temp:size()[1], y_temp:size()[2], y_temp:size()[3] );
    uv_images = uv_temp
    y_images = y_temp

    for count=2,images:size()[1] do
        yuv_temp = image.rgb2yuv(images[count]);
        yuv_temp = image.scale(yuv_temp,28,28,'bilinear')
        uv_temp = yuv_temp[{{2,3}}]
        y_temp = yuv_temp[{{1}}]

        uv_temp = uv_temp:reshape(1,uv_temp:size()[1], uv_temp:size()[2], uv_temp:size()[3]);
        y_temp = y_temp:reshape(1,y_temp:size()[1], y_temp:size()[2], y_temp:size()[3] );

        uv_images = torch.cat(uv_images,uv_temp,1)
        y_images = torch.cat(y_images,y_temp,1)
    end
    return uv_images,y_images
end


function get_file_names()
    local image_dir = '../../Data/tiny-imagenet-200/test/images/'
    local max_count = num_images;
    file_names = {};

    for file in lfs.dir(image_dir) do
        if string.match(file, ".JPEG") then
            table.insert(file_names,file)
        end
    end
    return file_names;
end

function get_image_batch(num_images)
    local image_dir = '../../Data/tiny-imagenet-200/test/images/'
    local max_count = num_images;
    local count = 1;
    local im_batch = nil
    local file_names = get_file_names();
    local num_files = #file_names
    
    for count=1,num_images-1 do
        rand_index = math.random(1,num_files);
        file = file_names[rand_index];
        local image_path = image_dir .. file
        local im = image.load(image_path);
        local im_size = im:size();
        
        im = im:reshape(1,im_size[1],im_size[2],im_size[3])

            if count == 1 then
                hc_batch = hc_temp
                im_batch = im
            end
        im_batch = torch.cat(im_batch,im,1)
    
    end
    return im_batch
end
