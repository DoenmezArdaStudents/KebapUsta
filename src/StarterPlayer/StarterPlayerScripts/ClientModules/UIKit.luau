-- Small UI toolkit shared by the HUD and the laptop: instance construction, styling helpers and
-- reusable animations (hover/press feedback, slide/fade, number count-up, pulse loops).

local TweenService = game:GetService("TweenService")

local Sound = require(script.Parent.Sound)

local Kit = {}

Kit.F = {
	regular = Enum.Font.BuilderSans,
	medium = Enum.Font.BuilderSansMedium,
	bold = Enum.Font.BuilderSansBold,
	black = Enum.Font.BuilderSansExtraBold,
	mono = Enum.Font.RobotoMono,
}

-- HUD palette (dark glass)
Kit.T = {
	glass = Color3.fromRGB(14, 14, 18),
	glass2 = Color3.fromRGB(32, 32, 40),
	text = Color3.fromRGB(248, 246, 242),
	dim = Color3.fromRGB(176, 172, 168),
	accent = Color3.fromRGB(232, 72, 48),
	gold = Color3.fromRGB(255, 196, 64),
	green = Color3.fromRGB(80, 214, 120),
	orange = Color3.fromRGB(255, 160, 50),
	red = Color3.fromRGB(240, 76, 64),
	blue = Color3.fromRGB(86, 156, 255),
}

function Kit.new(class: string, props: { [string]: any }?, children: { Instance }?): any
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				(o :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = o
		end
	end
	if props and props.Parent then
		o.Parent = props.Parent
	end
	return o
end
local new = Kit.new

function Kit.corner(r: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10) })
end

function Kit.round(): UICorner
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Kit.stroke(color: Color3?, transparency: number?, thickness: number?): UIStroke
	return new("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Transparency = transparency or 0.88,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Kit.pad(l: number, t: number?, r: number?, b: number?): UIPadding
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingTop = UDim.new(0, t or l),
		PaddingRight = UDim.new(0, r or l),
		PaddingBottom = UDim.new(0, b or t or l),
	})
end

function Kit.list(horizontal: boolean?, padding: number?, halign: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return new("UIListLayout", {
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 0),
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Kit.gradient(c1: Color3, c2: Color3, rotation: number?, t1: number?, t2: number?): UIGradient
	return new("UIGradient", {
		Color = ColorSequence.new(c1, c2),
		Rotation = rotation or 90,
		Transparency = NumberSequence.new(t1 or 0, t2 or t1 or 0),
	})
end

-- dark translucent "glass" card used across the HUD
function Kit.glass(props: { [string]: any }, radius: number?, class: string?): any
	props.BackgroundColor3 = props.BackgroundColor3 or Kit.T.glass
	props.BackgroundTransparency = props.BackgroundTransparency or 0.22
	props.BorderSizePixel = 0
	local f = new(class or "Frame", props, { Kit.corner(radius or 12), Kit.stroke(nil, 0.86) })
	-- subtle top highlight
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 212)),
		Rotation = 90,
		Parent = f,
	})
	return f
end

function Kit.label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or Kit.T.text
	props.Font = props.Font or Kit.F.medium
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextSize = props.TextSize or 15
	props.RichText = true
	props.BorderSizePixel = 0
	return new("TextLabel", props)
end

function Kit.tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

-- endless gentle pulse of one property between two values
function Kit.pulse(obj: Instance, prop: string, a: any, b: any, period: number?): Tween
	(obj :: any)[prop] = a
	local tw = TweenService:Create(obj, TweenInfo.new(period or 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { [prop] = b })
	tw:Play()
	return tw
end

-- UIScale-based hover / press feedback for any GuiButton
function Kit.hover(btn: GuiButton, amount: number?)
	local s = btn:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = btn })
	local up = 1 + (amount or 0.04)
	btn.MouseEnter:Connect(function()
		Kit.tween(s, 0.18, { Scale = up })
	end)
	btn.MouseLeave:Connect(function()
		Kit.tween(s, 0.22, { Scale = 1 })
	end)
	btn.MouseButton1Down:Connect(function()
		Kit.tween(s, 0.08, { Scale = 0.94 })
	end)
	btn.MouseButton1Up:Connect(function()
		Kit.tween(s, 0.25, { Scale = up }, Enum.EasingStyle.Back)
	end)
end

function Kit.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	props.BackgroundColor3 = props.BackgroundColor3 or Kit.T.accent
	props.TextColor3 = props.TextColor3 or Kit.T.text
	props.Font = props.Font or Kit.F.bold
	props.TextSize = props.TextSize or 15
	props.AutoButtonColor = false
	props.BorderSizePixel = 0
	local radius = props.Radius or 8
	props.Radius = nil
	local quiet = props.Quiet
	props.Quiet = nil
	local b = new("TextButton", props, { Kit.corner(radius) })
	Kit.hover(b)
	if onClick then
		b.Activated:Connect(function()
			if not quiet then
				Sound.Play("click")
			end
			onClick()
		end)
	end
	return b
end

-- animate a number shown in a label (money, percent …)
function Kit.countTo(label: TextLabel, from: number, to: number, format: (number) -> string, duration: number?)
	local nv = Instance.new("NumberValue")
	nv.Value = from
	local conn = nv.Changed:Connect(function(v)
		label.Text = format(v)
	end)
	local tw = TweenService:Create(nv, TweenInfo.new(duration or 0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Value = to })
	tw.Completed:Connect(function()
		conn:Disconnect()
		label.Text = format(to)
		nv:Destroy()
	end)
	tw:Play()
end

-- pop-in: scale from small with an overshoot
function Kit.pop(obj: GuiObject, from: number?, t: number?, delay: number?)
	local s = obj:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = obj })
	s.Scale = from or 0.6
	Kit.tween(s, t or 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
end

function Kit.clear(frame: Instance, keep: { string }?)
	for _, c in ipairs(frame:GetChildren()) do
		local k = false
		for _, cls in ipairs(keep or {}) do
			if c:IsA(cls) then
				k = true
			end
		end
		if not k then
			c:Destroy()
		end
	end
end

-- simple horizontal progress bar; returns (bar, fill)
function Kit.bar(props: { [string]: any }, color: Color3, bg: Color3?): (Frame, Frame)
	props.BackgroundColor3 = bg or Color3.fromRGB(255, 255, 255)
	props.BackgroundTransparency = props.BackgroundTransparency or (bg and 0 or 0.85)
	props.BorderSizePixel = 0
	local b = new("Frame", props, { Kit.round() })
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BorderSizePixel = 0, Parent = b }, { Kit.round() })
	return b, fill
end

return Kit
