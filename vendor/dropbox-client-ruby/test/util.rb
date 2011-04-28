require 'mechanize'



def login_and_authorize(authorize_url, config)
    a = WWW::Mechanize.new
    a.get(authorize_url) do |page|
        login_form = page.form_with(:action => '/login')
                
        login_form.login_email  = config['testing_user']
        login_form.login_password = config['testing_password']
        auth_page = login_form.submit()
        
        auth_form = auth_page.form_with(:action => 'authorize')
        if auth_form
            auth_button = auth_form.button_with(:value => "Allow")
            auth_form.click_button
        end 
        
    end
end
