require 'bundler/setup'
Bundler.require
require 'sinatra/reloader' if development?
require 'securerandom'
require 'json'
require 'base64'

Dotenv.load

Aws.config[:region] = "us-east-1"
Aws.config[:access_key_id] = ENV["ACCESS_KEY"]
Aws.config[:secret_access_key] = ENV["ACCESS_SECRET"]

class App < Sinatra::Base

  REKOG = Aws::Rekognition::Client.new(region: "us-east-1")
  S3 = Aws::S3::Resource.new(
      region: 'us-east-1',
      force_path_style: true,
      )

  TRS = client = Aws::Translate::Client.new(region: 'us-east-1')

  VALID_NUTRS = ['FIBTG', 'NIA','FOLDFE','CA','K','MG','FE','VITB6A','RIBF','TOCPHA','VITA_RAE', 'VITC','VITD','THIA']
  NEED_AMOUNT_BY_NUTRS = {
    FIBTG: 20.0,      # g 食物繊維
    NIA: 15.0,        # mg ナイアシン
    FOLDFE: 240.0,    # aeg 葉酸
    CA: 725.0,        # mg カルシウム
    K: 2500.0,        # mg カリウム
    MG: 360.0,        # mg マグネシウム
    FE: 7.5,          # mg 鉄
    VITB6A: 1.4,      # mg ビタミンb6
    RIBF: 1.6,        # mg ビタミンB2
    TOCPHA: 6.5,      # mg ビタミンE
    VITA_RAE: 900.0,  # aeg ビタミンa
    VITC: 100.0,      # mg  ビタミンC
    THIA: 1.4         # mg ビタミンB1
  }

  UNIT_BY_NUTRS = {
    FIBTG: 'g',      # g 食物繊維
    NIA: 'mg',        # mg ナイアシン
    FOLDFE: 'μg',    # aeg 葉酸
    CA: 'mg',        # mg カルシウム
    K: 'mg',        # mg カリウム
    MG: 'mg',        # mg マグネシウム
    FE: 'mg',          # mg 鉄
    VITB6A: 'mg',      # mg ビタミンb6
    RIBF: 'mg',        # mg ビタミンB2
    TOCPHA: 'mg',      # mg ビタミンE
    VITA_RAE: 'μg',  # aeg ビタミンa
    VITC: 'mg',      # mg  ビタミンC
    THIA: 'mg'
  }

  VEGE_BY_LACKED_NUTRS = {
    FIBTG: ['グリンピース', 'おくら', 'にら'],      # g 食物繊維      グリンピース おくら にら
    NIA: ['とうもろこし', 'かぼちゃ' ,'そらまめ'],        # mg ナイアシン   とうもろこし かぼちゃ そらまめ
    FOLDFE: ['枝豆', 'アスパラガス' 'ブロッコリー'],    # aeg 葉酸           えだまめ あすぱらがす ぶろっこりー
    CA: ['小松菜', '春菊', 'チンゲンサイ'],        # mg カルシウム     こまつな しゅんぎく ちんげんさい
    K: ['里芋', 'さつまいも', 'ほうれんそう'],        # mg カリウム      さといも さつまいも ほうれんそう
    MG: ['枝豆', 'おくら', 'ゴボウ'],        # mg マグネシウム   えだまめ おくら ごぼう
    FE: ['枝豆', '小松菜', 'そらまめ'],          # mg 鉄             えだまめ こまつな そらまめ
    VITB6A: ['さつまいも', 'にんにく', 'ピーマン'],      # mg ビタミンb6        さつまいも にんにく 青ピーマン
    RIBF: ['そらまめ', 'アスパラガス', '小葱'],        # mg ビタミンB2        そらまめ あすぱらがす こねぎ
    TOCPHA: ['アボガド', 'かぼちゃ', '枝豆'],      # mg ビタミンE      あぼがど かぼちゃ えだまめ
    VITA_RAE: ['かぼちゃ', 'ニンジン', 'パプリカ'],  # aeg ビタミンa     かぼちゃ にんじん ぱぷりか
    VITC: ['ピーマン', 'にがうり', 'ブロッコリー'],      # mg  ビタミンC   青ピーマン にがうり ぶろっこりー
    THIA: ['えだまめ', 'そらまめ', 'さやえんどう']         # mg ビタミンB1    えだまめ そらまめ さやえんどう
  }

    MAIN_VEGE = {
      FIBTG: 'グリンピース',      # g 食物繊維
    NIA: 'とうもろこし',        # mg ナイアシン
    FOLDFE: 'ブロッコリー',    # aeg 葉酸
    CA: '小松菜',        # mg カルシウム
    K: 'さつまいも',        # mg カリウム
    MG: 'ゴボウ',        # mg マグネシウム
    FE: 'そらまめ',          # mg 鉄
    VITB6A: 'さつまいも',      # mg ビタミンb6
    RIBF: '小葱',        # mg ビタミンB2
    TOCPHA: 'アボガド',      # mg ビタミンE
    VITA_RAE: 'ニンジン',  # aeg ビタミンa
    VITC: 'ピーマン',      # mg  ビタミンC
    THIA: 'さやえんどう'
    }
    IMAGE_URL_BY_VEGETABLE = {
      'グリンピース' => 'https://spajam.s3.amazonaws.com/grin.jpeg',
      'おくら' => 'https://spajam.s3.amazonaws.com/okura.jpeg',
      'にら' => 'https://spajam.s3.amazonaws.com/nira.jpg',
      'とうもろこし' => 'https://spajam.s3.amazonaws.com/tomoro.jpeg',
      'かぼちゃ' => 'https://spajam.s3.amazonaws.com/kabocha.jpg',
      'そらまめ' => 'https://spajam.s3.amazonaws.com/soramamesai2677.jpeg',
      '枝豆' => 'https://www.nichireifoods.co.jp/media/wp-content/uploads/2020/04/2005_01edamame_01.jpg',
      'アスパラガス' => 'https://spajam.s3.amazonaws.com/aspara.jpeg',
      'ブロッコリー' => 'https://spajam.s3.amazonaws.com/broco.jpeg',
      '小松菜' => 'https://d1f5hsy4d47upe.cloudfront.net/86/869f454d544576e3a1a3d52d59bd425f_t.jpeg',
      '春菊' => '',
      'チンゲンサイ' => '',
      '里芋' => 'https://www.nichireifoods.co.jp/media/wp-content/uploads/2019/09/1909_08_taro-store_01.jpg',
     'さつまいも' => 'https://cdn.macaro-ni.jp/assets/img/shutterstock/shutterstock_398300035.jpg',
      'ほうれんそう' => '',
      'ゴボウ' => 'https://cdn.macaro-ni.jp/assets/img/shutterstock/shutterstock_317751104.jpg',
      'にんにく' => '',
      'ピーマン' => 'https://spajam.s3.amazonaws.com/piman.jpeg',
      '小葱' => 'https://caracoro.jp/cara/wp-content/uploads/2018/08/999105372301.jpg',
      'アボガド' => 'https://halmek.co.jp/media/uploads/a83948fed1c6b757b625b56e3c3c15051587379565.8518.jpg',
      'ニンジン' => 'https://cdn.macaro-ni.jp/assets/img/shutterstock/shutterstock_459404320.jpg',
      'パプリカ' => '',
      'にがうり' => '',
     'さやえんどう' => 'https://spajam.s3.amazonaws.com/sayaen.jpg'
    }

  def is_valid_param(data)
    NEED_AMOUNT_BY_NUTRS.each do |k, v|
      unless data.has_key?(k)
        return false
      end
    end
    true
  end

  def calc_lacked_nutrient(data)
    most_lacked_value = 1 / 0.0
    most_lacked_name = ''
    NEED_AMOUNT_BY_NUTRS.each do |k, v|
      value = data[k].to_f
      if value > v * 7
        next
      end
      percentile = value / v * 7
      if most_lacked_value > percentile
        most_lacked_value = percentile
        most_lacked_name = k
      end
    end
    most_lacked_name
  end

  def translate_en_to_jpn(word)
    resp = TRS.translate_text({
      text: word,
      source_language_code: "en",
      target_language_code: "ja"
    })
    resp.translated_text
  end

  def s3_spajam_bucket
    S3.bucket("spajam")
  end

  def put_to_s3(file, key)
    s3_spajam_bucket.object(key).upload_file(file)
  end

  def parse_labels(labels)
    food_name = ""
    labels.each do |label|
      puts label.name
    end
    labels.each do |label|
      unless ['Food', 'Dish', 'Meal', 'Bowl', 'Plant', 'Soup Bowl', 'Dessert', 'Computer Hardware', 'Electronics', 'Hardware', 'Keyboard', 'Computer Keyboard', 'Computer', 'Lighting', 'Pc', 'Table', 'Sitting', 'Display', 'Monitor', 'Laptop', 'LCD Screen', 'Furniture'].include?(label.name)
        food_name = label.name
        break
      end
    end
  food_name
  end

  def trim_nutritions(nutrs)
    new_nutrs = {}
    nutrs.each do |k, v|
      unless VALID_NUTRS.include?(k)
        next
      end
      v["quantity"] = v["quantity"].floor(3)
      new_nutrs[k] = v
    end
    new_nutrs
  end

  def parse_edamam_response(res)
    nutritions = res["hits"][0]["recipe"]["totalNutrients"]
    nutritions
  end

  def search_recipe(name)
    edamam_uri = URI('https://api.edamam.com/search')
    params = {
      q: name,
      app_id: ENV["EDAMAM_ID"],
      app_key: ENV["EDAMAM_SECRET"],
      to: 1
    }
    edamam_uri.query = URI.encode_www_form(params)
    res = Net::HTTP.get_response(edamam_uri)
    edamam_body = JSON.parse(res.body)
    edamam_body
  end


  get '/admin' do
    erb :index
  end

  get '/health' do
    status 200
    JSON({message: "ok" })
  end

  get '/base64' do
    name =''
    image = File.read("./#{name}")
    b64_image = Base64.strict_encode64(image)
    b64_image
  end

  post '/test' do
    params = JSON.parse request.body.read
    base64_image = params["file"]
    chomped = base64_image.gsub(/[\r\n]/,"")
    File.open("base64log.txt", mode = "a"){|f|
      f.write(chomped)
      f.write("\n\n\n")
    }
    uuid = SecureRandom.uuid
    file = Tempfile.new([uuid,'.png'])
    file.write Base64.decode64(chomped)

    err = put_to_s3(file.path, uuid)


    return JSON({message: "success" })
  end



  get '/nutrients/list' do
    content_type :json
    res = {}
    NEED_AMOUNT_BY_NUTRS.each do |k, v|
      res[k] = {daily_intake: v, unit: UNIT_BY_NUTRS[k]}
    end
    JSON(res)
  end

  get '/recomend/vegetable' do
    unless is_valid_param(params)
      status 400
      return 'invalid request'
    end
    lacked_nutrient = calc_lacked_nutrient(params)
    content_type :json
    if lacked_nutrient == ''
      return JSON({is_perfect: true, lacked_nutrient: '' })
    end
    veges = VEGE_BY_LACKED_NUTRS[lacked_nutrient]
    image_name = MAIN_VEGE[lacked_nutrient]
    image_url =  IMAGE_URL_BY_VEGETABLE[image_name]
    veges.delete(image_name)
    JSON({is_perfect: false, lacked_nutrient:lacked_nutrient,main_vegetable: image_name, main_vegetable_image_url:image_url ,other_vegetables: veges})
  end

  post '/analyze' do
    puts 'analyze start'
    params = JSON.parse request.body.read
    base64_image = params["file"]
    unless base64_image
      status 400
      return 'bad request'
    end
    chomped = base64_image.gsub(/[\r\n]/,"")
    uuid = SecureRandom.uuid
    file = Tempfile.new([uuid,'.png'])
    file.write Base64.decode64(chomped)
    err = put_to_s3(file.path, uuid)
    file.close
    unless err
      status 500
      return 'upload fail'
    end
    object_url = "https://spajam.s3.amazonaws.com/#{uuid}"
    food_name = ''
    result = REKOG.detect_labels({
        image: {
          s3_object: {
            bucket: "spajam",
            name: uuid
          },
        }
    })
    food_name = parse_labels(result.labels)
    if food_name == ''
      status 400
      return JSON({message: "cannot recognize food" })
    end
    edamam_res = search_recipe(food_name)
    if edamam_res["hits"].empty?
      status 400
      return JSON({message: "cannot recognize food" })
    end
    nutritions = parse_edamam_response(edamam_res)
    content_type :json
    JSON({food_name: translate_en_to_jpn(food_name), image_url: object_url, nutritions: trim_nutritions(nutritions)})
  end


end
