motion_require 'base'

module Formotion
  module RowType
    class StringRow < Base
      include BW::KVO

      # The new UITextField in a UITableViewCell
      # will be assigned this tag, if applicable.
      TEXT_FIELD_TAG=1000

      def keyboardType
        UIKeyboardTypeDefault
      end

      # Configures the cell to have a new UITextField
      # which is used to enter data. Consists of
      # 1) setting up that field with the appropriate properties
      # specified by `row` 2) configures the callbacks on the field
      # to call any callbacks `row` listens for.
      # Also does the layoutSubviews swizzle trick
      # to size the UITextField so it won't bump into the titleLabel.
      def build_cell(cell)
        cell.selectionStyle = self.row.selection_style || UITableViewCellSelectionStyleBlue
        field = UITextField.alloc.initWithFrame(CGRectZero)
        field.tag = TEXT_FIELD_TAG

        observe(self.row, "value") do |old_value, new_value|
          break_with_semaphore do
            update_text_field(new_value)
          end
        end

        field.clearButtonMode = UITextFieldViewModeWhileEditing
        field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter
        field.textAlignment = row.text_alignment || NSTextAlignmentRight

        field.keyboardType = keyboardType

        field.secureTextEntry = true if row.secure?
        field.returnKeyType = row.return_key || UIReturnKeyNext
        field.autocapitalizationType = row.auto_capitalization if row.auto_capitalization
        field.autocorrectionType = row.auto_correction if row.auto_correction
        field.clearButtonMode = row.clear_button || UITextFieldViewModeWhileEditing
        field.enabled = row.editable?
        field.inputAccessoryView = input_accessory_view(row.input_accessory) if row.input_accessory

        add_callbacks(field)

        cell.swizzle(:layoutSubviews) do
          def layoutSubviews
            old_layoutSubviews

            # viewWithTag is terrible, but I think it's ok to use here...
            formotion_field = self.viewWithTag(TEXT_FIELD_TAG)
            formotion_field.sizeToFit

            field_frame = formotion_field.frame
            field_frame.origin.x = self.textLabel.frame.origin.x + self.textLabel.frame.size.width + Formotion::RowType::Base.field_buffer
            field_frame.origin.y = ((self.frame.size.height - field_frame.size.height) / 2.0).round
            field_frame.size.width = self.frame.size.width - field_frame.origin.x - Formotion::RowType::Base.field_buffer
            formotion_field.frame = field_frame
          end
        end

        if UIDevice.currentDevice.systemVersion >= "6.0"
          field.swizzle(:setText) do
            def setText(text)
              r = old_setText(text)
              self.sendActionsForControlEvents(UIControlEventEditingChanged)
              r
            end
          end
        end

        field.font = BW::Font.new(row.font) if row.font
        field.placeholder = row.placeholder
        field.text = row_value
        cell.addSubview(field)
        field

      end

      # overriden in subclasses
      def row_value
        row.value.to_s
      end

      def add_callbacks(field)
        if row.on_enter_callback
          field.should_return? do |text_field|
            if row.on_enter_callback.arity == 0
              row.on_enter_callback.call
            elsif row.on_enter_callback.arity == 1
              row.on_enter_callback.call(row)
            end
            false
          end
        elsif field.returnKeyType == UIReturnKeyDone
          field.should_return? do |text_field|
            text_field.resignFirstResponder
            false
          end
        else
          field.should_return? do |text_field|
            if row.next_row && row.next_row.text_field
              row.next_row.text_field.becomeFirstResponder
            else
              text_field.resignFirstResponder
            end
            true
          end
        end

        field.on_end do |text_field|
          row.on_end_callback && row.on_end_callback.call
        end

        field.on_begin do |text_field|
          row.on_begin_callback && row.on_begin_callback.call
        end

        field.should_begin? do |text_field|
          row.section.form.active_row = row
          true
        end

        field.on_change do |text_field|
          on_change(text_field)
        end
      end

      def on_change(text_field)
        break_with_semaphore do
          row.value = text_field.text
        end
      end

      def on_select(tableView, tableViewDelegate)
        if row.editable?
          row.text_field.becomeFirstResponder
        end
      end

      # Used when row.value changes
      def update_text_field(new_value)
        self.row.text_field.text = row_value
      end

      # Creates the inputAccessoryView to show
      # if input_accessory property is set on row.
      # :done is currently the only supported option.
      def input_accessory_view(input_accessory)
        input_accessory = input_accessory.to_sym
        case input_accessory
        when :done
          @input_accessory ||= begin
            tool_bar = UIToolbar.alloc.initWithFrame([[0, 0], [0, 44]])
            tool_bar.autoresizingMask = UIViewAutoresizingFlexibleWidth
            tool_bar.translucent = true

            left_space = UIBarButtonItem.alloc.initWithBarButtonSystemItem(
                UIBarButtonSystemItemFlexibleSpace,
                target: nil,
                action: nil)

            done_button = UIBarButtonItem.alloc.initWithBarButtonSystemItem(
                UIBarButtonSystemItemDone,
                target: self,
                action: :done_editing)

            tool_bar.items = [left_space, done_button]

            tool_bar
          end
        else
          nil
        end
      end

      # Callback for "Done" button in input_accessory_view
      def done_editing
        self.row.text_field.endEditing(true)
      end

    end
  end
end
