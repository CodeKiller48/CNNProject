require 'Utils'
require 'nngraph';
require 'loadcaffe'
require 'image'
require 'VGG'
require 'optim'
require 'Net3' --IMP
require 'gnuplot'
require 'GradL1WeightedLoss'

local cmd = torch.CmdLine()

-- Dataset options
-- cmd:option('-input_h5', 'data/tiny-shakespeare.h5')
-- cmd:option('-input_json', 'data/tiny-shakespeare.json')
cmd:option('-batch_size', 6)

-- Optimization options
cmd:option('-num_iterations', 2000)
cmd:option('-learning_rate', 1e-6)
cmd:option('-grad_clip', 5)
-- cmd:option('-lr_decay_every', 5)
cmd:option('-lr_decay_factor', 0.9)
cmd:option('-tv_strength', 1e-3)

-- Output options
cmd:option('-print_every', 1)
cmd:option('-checkpoint_every', 31)
cmd:option('-checkpoint_name', '../../results/checkpoint_class')
cmd:option('-image_name', '../../results/image_checkpoint')
cmd:option('-plot_path', '../../results/')

-- Benchmark options
cmd:option('-speed_benchmark', 0)
cmd:option('-memory_benchmark', 0)

-- Backend options
cmd:option('-gpu', 0)
cmd:option('-gpu_backend', 'cuda')

-- Load Model/Data
cmd:option('-load_model', true)
cmd:option('-model_path','../../results/checkpoint_class_201.t7')
cmd:option('-all_class', false)
cmd:option('-train_path','../../Data/tiny-imagenet-200/train/lemon_sky_elephant/images/')
cmd:option('-val_path','../../Data/tiny-imagenet-200/val/lemon_sky_elephant/')


local opt = cmd:parse(arg)


print("Loading the model...");
local dtype = 'torch.DoubleTensor'
-- Creating a new model
local model = create_colorNet();

-- Loading a pre-trained model
if opt.load_model then
    print("Loading the pretrained model: " .. opt.model_path);
    checkpoint_1 = torch.load(opt.model_path)
    model = checkpoint_1.model:type(dtype)
    print("Loaded the pretrained model: " .. opt.model_path);
end

print("Setting model into training model:");
print("all_classes: ");
print(opt.all_class);

model:training()
local params, grad_params = model:getParameters()
grad_params:zero()

local crit = nn.AbsCriterion():type(dtype)
-- local crit = nn.MSECriterion():type(dtype)

local L1gradcrit = nn.GradL1WeightedLoss(opt.tv_strength):type(dtype)

-- Set up some variables we will use below
local train_loss_history = {}
local val_loss_history = {}
local val_loss_history_it = {}

if opt.load_model then
    local train_loss_history = checkpoint_1.train_loss_history
    local val_loss_history = checkpoint_1.val_loss_history
    local val_loss_history_it = checkpoint_1.val_loss_history_it
end

-- Loss function that we pass to an optim method
local function f(w)
--  assert(w == params)

  im_batch = get_image_batch(opt.batch_size, opt.train_path) -- Generalizes

  x = torch.Tensor(im_batch:size()[1],im_batch:size()[2],224,224)

  for i=1,im_batch:size()[1] do
    x[i] = preprocess(im_batch[i])
  end
  uv_images, y_images = create_yuv_images(im_batch,56,56)
  x, uv_images = x:type(dtype), uv_images:type(dtype)
--   local y = uv_images + 0.5
  local y = uv_images*2
    
  local scores = model:forward(x)
--   print (scores:size())
  local loss   = crit:forward(scores, y)
  L1gradloss   = L1gradcrit:forward(scores, y)

  -- Run the Criterion and model backward to compute gradients, maybe timing it
  local grad_scores = crit:backward(scores, y)
    
  local L1grad_score = L1gradcrit:backward(scores,y)
  
--   print(torch.mean(grad_scores:cdiv(L1grad_score):abs() ) )
--   print(torch.norm(grad_scores))
--   print(torch.norm(L1grad_score))
  model:backward(x, grad_scores + L1grad_score)

--   if opt.grad_clip > 0 then
--     grad_params:clamp(-opt.grad_clip, opt.grad_clip)
--   end
  return loss, grad_params
end


print("Training starts! initial learning rate: " .. opt.learning_rate );
-- Train the model!
local optim_config = {learningRate = opt.learning_rate}
local num_iterations = opt.num_iterations
for i = 1, num_iterations do

  -- Take a gradient step and maybe print
  -- Note that adam returns a singleton array of losses
  local _, loss = optim.adam(f, params, optim_config)
  table.insert(train_loss_history, loss[1])
  if opt.print_every > 0 and i % opt.print_every == 0 then
    local msg = ' i = %d / %d, loss = %f, L1gradloss = %f'
    local args = {msg,  i, num_iterations, loss[1], L1gradloss}
    print(string.format(unpack(args)))
  end
    
  -- Maybe save a checkpoint 
  local check_every = opt.checkpoint_every
  if (check_every > 0 and (i-1) % check_every == 0) or i == num_iterations then
    print("Evaluating on val dataset")
    -- Evaluate loss on the validation set. Note that we reset the state of
    -- the model; this might happen in the middle of an epoch, but that
    -- shouldn't cause too much trouble.

    
    model:clearState()
    
    -- Going to test mode.
    model:evaluate()
    
    local im_batch = get_validation_batch(opt.batch_size, opt.val_path, true)
    local x = torch.Tensor(im_batch:size()[1],im_batch:size()[2],224,224)

    for k=1,im_batch:size()[1] do
        x[k] = preprocess(im_batch[k])
    end
    local uv_images, y_images = create_yuv_images(im_batch,56,56)
    local x, uv_images = x:type(dtype), uv_images:type(dtype)
--     local y = uv_images + 0.5
    local y = uv_images*2

    local scores = model:forward(x)
    local val_loss = crit:forward(scores, y) 
    local val_L1gradloss   = L1gradcrit:forward(scores, y)
    local uv_op = model.output*0.5
        
    print('val_loss = ', val_loss)
    print('val_L1gradloss = ', val_L1gradloss)
    table.insert(val_loss_history, val_loss)
    table.insert(val_loss_history_it, i)
   
--     params, grad_params = model:getParameters()
    
    local checkpoint = {
      opt = opt,
      train_loss_history = train_loss_history,
      val_loss_history = val_loss_history,
      val_loss_history_it = val_loss_history_it,
    }

    -- Saving the plots
    local filename = string.format('../../results/train_history.png' )
    gnuplot.pngfigure(filename)
    gnuplot.plot(torch.Tensor(train_loss_history))
    gnuplot.plotflush()
    
    local filename = string.format('../../results/val_history.png')
    gnuplot.pngfigure(filename)
    gnuplot.plot(torch.Tensor(val_loss_history))
    gnuplot.plotflush()

    -- Save the model
        
    model:clearState()
    checkpoint.model = model
    print("Saving model checkpoint: ")
    local filename = string.format('%s_%d.t7', opt.checkpoint_name, i)
    paths.mkdir(paths.dirname(filename))
    torch.save(filename, checkpoint)
    print("Checkpoint Saved: ".. filename)
    
    -- Saving the images
    print("Saving images: ")
    local imagepath = string.format('%s_%d/', opt.image_name, i)
    paths.mkdir(imagepath)
    
    for j = 1,opt.batch_size do
        local size = 112
        local input_imagename =  string.format('%sinput_%d.png', imagepath, j)
        image.save(input_imagename, image.scale(y2rgb(image.rgb2y(im_batch[j])),size,size))
        
        local output_imagename =  string.format('%soutput_%d.png', imagepath, j)
        local output_image = image.scale(image.yuv2rgb(torch.cat(y_images[j],uv_op[j],1)),size,size)   
        image.save(output_imagename,output_image)        
        
        local original_imagename =  string.format('%sorig_%d.png', imagepath, j)
        local orig_image = image.scale(image.yuv2rgb(torch.cat(y_images[j],uv_images[j],1)),size,size)
        image.save(original_imagename,orig_image)        
    end
    
        
    -- Back to training mode
    model:training()
    local old_lr = optim_config.learningRate
    optim_config = {learningRate = old_lr * opt.lr_decay_factor}
    print("New learning rate: " .. optim_config.learningRate );    
    collectgarbage()  
    
  end
end
