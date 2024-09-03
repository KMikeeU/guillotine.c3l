module guillotine;

import glfw;
import gl;
import blend2d;

import std::io;


fault GuillotineFault {
    GLFW_FAILED,
    BLEND2D_FAILED
}

def Color = float[<4>];

struct Area {
    int[<2>] position;
    int[<2>] size;
}

struct FontManager {
    BLFontManagerCore* blfontManager;
    String defaultFont;
}

fn void! FontManager.init(FontManager* self) {
    BLResult result;
    self.blfontManager = mem::new(BLFontManagerCore);

    result = blend2d::font_manager::init(self.blfontManager);
    if (result != blend2d::BL_SUCCESS) {
        io::printn("Failed to init font manager");
        return GuillotineFault.BLEND2D_FAILED?;
    }

    result = blend2d::font_manager::create(self.blfontManager);
    if (result != blend2d::BL_SUCCESS) {
        io::printn("Failed to init font manager");
        return GuillotineFault.BLEND2D_FAILED?;
    }

    self.defaultFont = "arial";

    DString fontfilename = dstring::new(self.defaultFont);
    fontfilename.append(".ttf");
    defer fontfilename.free();

    // Some default paths according to copilot
    Path[] searchPaths = {
        path::new("C:\\Windows\\Fonts")!!,
        path::new("/usr/share/fonts")!!,
        path::new("/usr/local/share/fonts")!!,
        path::new("/usr/share/fonts/truetype")!!,
        path::new("/usr/local/share/fonts/truetype")!!
    };

	blend2d::BLFontFaceCore* fontface = mem::new(blend2d::BLFontFaceCore);

    result = blend2d::font_face::init(fontface);
	if(result != blend2d::BL_SUCCESS) {
		return GuillotineFault.BLEND2D_FAILED?;
	}

    foreach (Path path : searchPaths) {
        String fontPath = path.append(fontfilename.str_view())!!.absolute()!!.str_view();
        result = blend2d::font_face::create_from_file(fontface, (ZString)fontPath, blend2d::BL_FILE_READ_NO_FLAGS);
        if (result == blend2d::BL_SUCCESS) {
            break;
        }
    }

    result = blend2d::font_manager::add_face(self.blfontManager, fontface);
    if (result != blend2d::BL_SUCCESS) {
        return GuillotineFault.BLEND2D_FAILED?;
    }
}

fn blend2d::BLFontFaceCore* FontManager.query(FontManager* self, String fontName) {
    BLFontFaceCore* fontFace = mem::new(BLFontFaceCore);
    blend2d::font_face::init(fontFace);

    BLResult result = blend2d::font_manager::query_face(self.blfontManager, (ZString)fontName, fontName.len, &&BLFontQueryProperties{1, 1, 1}, fontFace);
        
    if (result != blend2d::BL_SUCCESS) {
        return null;
    }

    return fontFace;
}

struct Guillotine (Parent) {
    glfw::Window* window;
    bool isDebug;
    BLContextCore* ctx;
    BLImageCore* img;
    FontManager* fontManager;


    Color clearColor;
    Drawable root;
}


fn void key_callback(Window* window, glfw::key::Key key, CInt scancode, glfw::key::Action action, CInt mods) {
    Guillotine* gui = (Guillotine*)glfw::get_window_user_pointer(window);

    if (gui == null) {
        io::printn("FATAL: No user pointer set on window");
        return;
    }

    if (gui.isDebug) {
        io::printfn("Key: %d, Scancode: %d, Action: %d, Mods: %d", key, scancode, action, mods);
    }
}

fn void! Guillotine.init(Guillotine* self, bool debug = true) {
    self.isDebug = debug;
    self.ctx = mem::new(BLContextCore);
    self.img = mem::new(BLImageCore);

    self.fontManager = mem::new(FontManager);
    self.fontManager.init()!!;

    if(!glfw::init()) {
        return GuillotineFault.GLFW_FAILED?;
    }

    self.window = glfw::create_window(720, 480, "Guillotine", null, null);

    if (self.window == null) {
		return GuillotineFault.GLFW_FAILED?;
	}

    glfw::set_window_user_pointer(self.window, self);

    glfw::make_context_current(self.window);
    glfw::set_key_callback(self.window, &key_callback);

    BLResult result;
    result = blend2d::image::init(self.img);
	if (result != blend2d::BL_SUCCESS) {
		return GuillotineFault.BLEND2D_FAILED?;
	}

    result = blend2d::image::create(self.img, 720, 480, blend2d::BL_FORMAT_PRGB32);
	if (result != blend2d::BL_SUCCESS) {
		return GuillotineFault.BLEND2D_FAILED?;
    }

    result = blend2d::context::init(self.ctx);
	if (result != blend2d::BL_SUCCESS) {
        return GuillotineFault.BLEND2D_FAILED?;
    }

}

fn void! Guillotine.destroy(Guillotine* self) {
    blend2d::context::destroy(self.ctx);

    blend2d::image::destroy(self.img);

    glfw::destroy_window(self.window);

    glfw::terminate();
}

fn bool Guillotine.is_running(Guillotine* self) {
    return !glfw::window_should_close(self.window);
}


fn void Guillotine.begin(Guillotine* self) {
    glfw::poll_events();
    
    // TODO: Why is the clear color always the same?
    // gl::clear_color(self.clearColor.r, self.clearColor.g, self.clearColor.b, self.clearColor.a);
    gl::clear_color(1.0, 1.0, 1.0, 1.0);
    gl::clear(gl::COLOR_BUFFER_BIT);

    // Flip the image back to normal
    gl::raster_pos_2f(-1.0, 1.0);
    gl::pixel_zoom(1.0, -1.0);

    blend2d::context::begin(self.ctx, self.img, null);
}

// This is a bit hacky
// Blend2d uses BGRA in the raw data for some reason
// Opengl only widely supports RGBA apparently
fn void bgra_to_rgba(char* data, long size) {
	for (long i = 0; i < size; i += 4) {
		char tmp = data[i];
		data[i] = data[i + 2];
		data[i + 2] = tmp;
	}
}

fn void Guillotine.end(Guillotine* self) {
    blend2d::context::end(self.ctx);

    BLImageData data;
    BLResult result = blend2d::image::get_data(self.img, &data);
    // if (result != blend2d::BL_SUCCESS) {
    //     return GuillotineFault.BLEND2D_FAILED?;
    // }

    char* pixelData = (char*)data.pixelData;

    bgra_to_rgba(pixelData, (long)(data.size.w * data.size.h) * 4);
    gl::draw_pixels(data.size.w, data.size.h, 0x1908, 0x1401, data.pixelData);


    glfw::swap_buffers(self.window);
}

fn any Guillotine.with(Guillotine* self, Drawable child) @dynamic {
    self.root = child;
    return (any)self;
}


fn void Guillotine.draw_all(Guillotine* self) {
    if (self.root != null) {
        // TODO: This should be the size of the window/image
        Area area = Area{{0, 0}, {720, 480}};

        self.root.draw(self, area);
    }
}


module guillotine::components;

import std::io;
import std::collections::list;

import blend2d;

enum Direction {
    HORIZONTAL,
    VERTICAL
}

enum ConstraintValueType {
    ABSOLUTE,
    RELATIVE
}

struct ConstraintValue {
    ConstraintValueType type;
    float value;
}

def ConstraintValueList = List(<ConstraintValue>)*;

struct Constraints {
    Direction direction;
    ConstraintValueList values;
}

interface Drawable {
    fn void draw(Guillotine* gui, Area area);
}

interface Parent {
    fn any with(Drawable child);
}

interface Colorable {
    fn any with_color(Color color);
}



// -------------
// Background
// -------------

struct Background (Drawable, Parent, Colorable) {
    Color color;
    Drawable child;
}

fn void Background.draw(Background* self, Guillotine* gui, Area area) @dynamic {

    blend2d::context::set_fill_style_rgba(gui.ctx, &&blend2d::BLRgba{self.color.r, self.color.g, self.color.b, self.color.a});
    
    blend2d::context::fill_rect_i(gui.ctx, &&BLRectI{
        area.position.x,
        area.position.y,
        area.size.x,
        area.size.y
    });

    if (self.child != null) {
        self.child.draw(gui, area);
    }
}

fn any Background.with(Background* self, Drawable child) @dynamic {
    self.child = child;
    return (any)self;
}

fn any Background.with_color(Background* self, Color color) @dynamic {
    self.color = color;
    return (any)self;
}


// -------------
// Container
// -------------

struct Container (Drawable, Parent) {
    int[<4>] padding;
    Drawable child;
}

fn void Container.draw(Container* self, Guillotine* gui, Area area) @dynamic {
    Area childArea = Area{{area.position[0] + self.padding[0], area.position[1] + self.padding[1]}, {area.size[0] - self.padding[0] - self.padding[2], area.size[1] - self.padding[1] - self.padding[3]}};

    if (self.child != null) {
        self.child.draw(gui, childArea);
    }
}

fn any Container.with(Container* self, Drawable child) @dynamic {
    self.child = child;
    return (any)self;
}


// -------------
// Layout
// -------------

struct Layout (Drawable, Parent) {
    int spacing;
    Constraints constraints;
    List(<Drawable>)* children;
}

fn void Layout.draw(Layout* self, Guillotine* gui, Area area) @dynamic {
    // If there are no children, not every child has exactly one constraint, bail
    if (self.children.len() == 0 || self.constraints.values.len() != self.children.len()) {
        return;
    }

    int length = (int)self.children.len();

    int total = area.size[self.constraints.direction];
    int remaining = total;

    foreach (index, constraint : self.constraints.values) {
        int pixelSize;
        if (constraint.type == ConstraintValueType.ABSOLUTE) {
            pixelSize = (int)constraint.value;
        } else {
            pixelSize = (int)( (float)(total - ((length-1)*self.spacing)) * constraint.value);
        }

        
        if (self.constraints.direction == Direction.HORIZONTAL) {
            Area childArea = Area{
                {area.position[0] + total - remaining, area.position[1]},
                {pixelSize, area.size[1]}
            };
            (self.children.get(index)).draw(gui, childArea);
        } else {
            Area childArea = Area{
                {area.position[0], area.position[1] + total - remaining},
                {area.size[0], pixelSize}
            };
            (self.children.get(index)).draw(gui, childArea);
        }

        remaining -= pixelSize + self.spacing;
    }
}

fn any Layout.with(Layout* self, Drawable child) @dynamic {
    self.children.push(child);
    return (any)self;
}


// -------------
// Label
// -------------

struct Label (Drawable) {
    float size;
    Color color;
    String text;
    BLFontCore* font;
}

fn void Label.draw(Label* self, Guillotine* gui, Area area) @dynamic {
    blend2d::context::set_fill_style_rgba(gui.ctx, &&blend2d::BLRgba{
        self.color.r,
        self.color.g,
        self.color.b,
        self.color.a
    });
    blend2d::context::fill_utf8_text_i(gui.ctx, &&BLPointI{area.position[0], area.position[1] + (int)self.size}, self.font, (ZString)self.text, self.text.len);
}

fn Label*! Guillotine.label(Guillotine* gui, String text, float size = 16.0, Color color = {0.0, 0.0, 0.0, 1.0}) {
    io::printn("Creating label");
    blend2d::BLFontFaceCore* fontface = gui.fontManager.query(gui.fontManager.defaultFont);
    blend2d::BLFontCore* font = mem::new(blend2d::BLFontCore);

    io::printn("Got fontface");

    BLResult result = blend2d::font::init(font);
    if (result != blend2d::BL_SUCCESS) {
        return GuillotineFault.BLEND2D_FAILED?;
    }

    result = blend2d::font::create_from_face(font, fontface, size);
    if (result != blend2d::BL_SUCCESS) {
        return GuillotineFault.BLEND2D_FAILED?;
    }

    Label* label = mem::new(Label);
    label.color = color;
    label.size = size;
    label.text = text;
    label.font = font;
    return label;
}
